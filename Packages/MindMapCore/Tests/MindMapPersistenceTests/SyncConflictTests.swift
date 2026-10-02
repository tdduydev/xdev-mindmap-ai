import Foundation
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import Synchronization
import Testing

/// The *Conflicts* table of cloudkit-sync.md, on two simulated devices
/// (FR-SYN-04, FR-SYN-05). Each device has its own store and an open editor;
/// a third store plays CloudKit's private database. A push writes a device's
/// change sets to it record by record, so the last push wins per record, as
/// mirroring does; a pull writes what differs back into the device's store,
/// and the editor takes it in with `takeStored`, as the app does on a remote
/// change. Real devices are a manual test (docs/cloudkit-sync.md, *Testing*).
@Suite("Sync conflicts")
struct SyncConflictTests {
    /// Every reading one second later, shared by both devices, so "later" means later.
    final class Clock: Sendable {
        private let current = Mutex(Date(timeIntervalSinceReferenceDate: 800_000_000))
        var now: Date { current.withLock { $0 } }
        var ticking: @Sendable () -> Date {
            { [self] in current.withLock { $0 = $0.addingTimeInterval(1); return $0 } }
        }
    }

    struct Device {
        let store: SwiftDataMapRepository
        var editor: GraphEngine
        /// Saved here, not pushed yet.
        var outbox: [GraphChangeSet] = []

        var state: GraphState { editor.state }

        mutating func edit(_ command: any GraphCommand) async throws {
            let changes = try editor.execute(command)
            try await store.save(changes, map: editor.state.map)
            outbox.append(changes)
        }
    }

    let clock = Clock()
    let cloud: SwiftDataMapRepository
    let mapID: MapID
    /// Built on device A, synced to B before each test edits.
    let ids: [String: NodeID]
    var a: Device
    var b: Device

    /// Root ▸ X ▸ X1, and Root ▸ Y.
    init() async throws {
        cloud = try PersistenceController.makeRepository(at: .inMemory)
        var engine = try GraphEngine(state: GraphState.newMap(title: "Shared", now: Date(timeIntervalSinceReferenceDate: 800_000_000)), clock: clock.ticking)
        let root = try #require(engine.state.map.rootNodeID)
        let x = NodeID(), x1 = NodeID(), y = NodeID()
        try engine.execute(AddNodeCommand(nodeID: x, .child(of: root), title: "X"))
        try engine.execute(AddNodeCommand(nodeID: x1, .child(of: x), title: "X1"))
        try engine.execute(AddNodeCommand(nodeID: y, .child(of: root), title: "Y"))
        let base = engine.state
        mapID = base.map.id
        ids = ["Root": root, "X": x, "X1": x1, "Y": y]
        try await cloud.create(base)
        a = try await Self.device(from: base, clock: clock)
        b = try await Self.device(from: base, clock: clock)
    }

    private static func device(from base: GraphState, clock: Clock) async throws -> Device {
        let store = try PersistenceController.makeRepository(at: .inMemory)
        try await store.create(base)
        return Device(store: store, editor: try GraphEngine(state: base, clock: clock.ticking))
    }

    private func push(_ device: inout Device) async throws {
        for changes in device.outbox {
            try await cloud.save(changes, map: device.editor.state.map)
        }
        device.outbox = []
    }

    /// Brings the device's store to what the cloud holds, or to `partial` of it.
    private func pull(_ device: inout Device, only partial: ((GraphState, GraphState) -> GraphState)? = nil) async throws {
        let mine = try #require(try await device.store.loadGraph(for: mapID))
        var server = try #require(try await cloud.loadGraph(for: mapID))
        if let partial { server = partial(mine, server) }
        try await device.store.save(GraphChangeSet.difference(from: mine, to: server), map: server.map)
        let stored = try #require(try await device.store.loadGraph(for: mapID))
        _ = try device.editor.takeStored(stored, now: clock.now)
    }

    private mutating func syncBoth() async throws {
        try await push(&a)
        try await push(&b)
        try await pull(&a)
        try await pull(&b)
    }

    /// The devices agree, the graph is valid, and every topic is still there.
    private func expectConverged(keeping expected: Set<NodeID>, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(a.state == b.state, "devices disagree", sourceLocation: sourceLocation)
        #expect(GraphValidator.validate(a.state).isEmpty, sourceLocation: sourceLocation)
        #expect(expected.isSubset(of: Set(a.state.nodes.keys)), "a topic was lost", sourceLocation: sourceLocation)
    }

    private var everyTopic: Set<NodeID> { Set(ids.values) }

    private subscript(title: String) -> NodeID {
        guard let id = ids[title] else { preconditionFailure("No topic titled \(title)") }
        return id
    }

    @Test mutating func editsOfDifferentTopicsBothSurvive() async throws {
        try await a.edit(UpdateNodeCommand(nodeID: self["X"], .title("X from A")))
        try await b.edit(UpdateNodeCommand(nodeID: self["Y"], .title("Y from B")))

        try await syncBoth()

        expectConverged(keeping: everyTopic)
        #expect(a.state.node(self["X"])?.title == "X from A")
        #expect(a.state.node(self["Y"])?.title == "Y from B")
    }

    @Test mutating func theLastWriterWinsForTheSameTopicOnly() async throws {
        try await a.edit(UpdateNodeCommand(nodeID: self["X"], .title("X from A")))
        try await a.edit(UpdateNodeCommand(nodeID: self["Y"], .title("Y from A")))
        try await b.edit(UpdateNodeCommand(nodeID: self["X"], .title("X from B")))

        try await syncBoth()

        expectConverged(keeping: everyTopic)
        #expect(a.state.node(self["X"])?.title == "X from B")
        #expect(a.state.node(self["Y"])?.title == "Y from A")
    }

    /// A's undo history keeps the Y step and loses the X step B overwrote.
    @Test mutating func undoOnTheLosingDeviceKeepsOnlyUntouchedSteps() async throws {
        try await a.edit(UpdateNodeCommand(nodeID: self["Y"], .title("Y from A")))
        try await a.edit(UpdateNodeCommand(nodeID: self["X"], .title("X from A")))
        try await b.edit(UpdateNodeCommand(nodeID: self["X"], .title("X from B")))

        try await syncBoth()
        let undoChanges = a.editor.undo()
        let undone = try #require(undoChanges)
        try await a.store.save(undone, map: a.editor.state.map)

        #expect(a.state.node(self["Y"])?.title == "Y")
        #expect(a.state.node(self["X"])?.title == "X from B")
        #expect(!a.editor.canUndo)
        let redoChanges = a.editor.redo()
        let redone = try #require(redoChanges)
        try await a.store.save(redone, map: a.editor.state.map)
        #expect(a.state.node(self["Y"])?.title == "Y from A")
        #expect(a.state.node(self["X"])?.title == "X from B")
    }

    /// The child shows under the root while its parent is on the way, and
    /// under its parent once that arrives: the repair is not saved.
    @Test mutating func aTopicThatArrivesBeforeItsParentWaitsUnderTheRoot() async throws {
        let parent = NodeID(), child = NodeID()
        try await a.edit(AddNodeCommand(nodeID: parent, .child(of: self["Y"]), title: "Parent"))
        try await a.edit(AddNodeCommand(nodeID: child, .child(of: parent), title: "Child"))
        try await push(&a)

        try await pull(&b) { mine, server in
            GraphState(map: mine.map, nodes: Array(mine.nodes.values) + [server.node(child)].compactMap(\.self), edges: Array(mine.edges.values))
        }
        #expect(b.state.node(child)?.parentID == ids["Root"])
        #expect(try await b.store.loadGraph(for: mapID)?.node(child)?.parentID == parent)

        try await pull(&b)
        try await pull(&a)
        #expect(b.state.node(child)?.parentID == parent)
        expectConverged(keeping: everyTopic.union([parent, child]))
    }

    @Test mutating func topicsAddedUnderABranchDeletedElsewhereHangUnderTheRoot() async throws {
        let added = NodeID()
        try await a.edit(DeleteNodeCommand(nodeID: self["X"]))
        try await b.edit(AddNodeCommand(nodeID: added, .child(of: self["X1"]), title: "Added on B"))

        try await syncBoth()

        expectConverged(keeping: [self["Root"], self["Y"], added])
        #expect(a.state.node(added)?.title == "Added on B")
        let rootChildren = a.state.children(of: self["Root"]).map(\.id)
        let hangsUnderRoot = rootChildren.contains(added) || rootChildren.contains(where: { a.state.node(added)?.parentID == $0 })
        #expect(hangsUnderRoot)
    }

    @Test mutating func movesUnderEachOtherAreCutTheSameWayOnBothDevices() async throws {
        try await a.edit(ReparentNodeCommand(nodeID: self["X"], newParentID: self["Y"]))
        try await b.edit(ReparentNodeCommand(nodeID: self["Y"], newParentID: self["X"]))

        try await syncBoth()

        expectConverged(keeping: everyTopic)
        // B moved last, so its move is the one cut: Y goes back under the root.
        #expect(a.state.node(self["Y"])?.parentID == ids["Root"])
        #expect(a.state.node(self["X"])?.parentID == ids["Y"])
    }

    /// Both devices edit offline for a while, then sync in either order.
    @Test mutating func theOrderOfPullsDoesNotChangeTheResult() async throws {
        let fromA = NodeID(), fromB = NodeID()
        try await a.edit(AddNodeCommand(nodeID: fromA, .child(of: self["X1"]), title: "From A"))
        try await a.edit(UpdateNodeCommand(nodeID: self["Y"], .note("Note from A")))
        try await b.edit(AddNodeCommand(nodeID: fromB, .child(of: self["Y"]), title: "From B"))
        try await b.edit(DeleteNodeCommand(nodeID: self["X"]))

        try await push(&b)
        try await push(&a)
        try await pull(&b)
        try await pull(&a)

        expectConverged(keeping: [self["Root"], self["Y"], fromA, fromB])
    }
}

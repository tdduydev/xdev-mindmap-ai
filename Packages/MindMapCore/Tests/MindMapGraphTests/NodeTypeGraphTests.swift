import Foundation
import MindMapDomain
@testable import MindMapGraph
import Testing

/// Runs primitives directly; the user commands for these records come with MM-60 to MM-66.
struct EditForTest: GraphCommand {
    let body: @Sendable (inout GraphTransaction) throws -> Void

    init(_ body: @escaping @Sendable (inout GraphTransaction) throws -> Void) {
        self.body = body
    }

    func execute(in transaction: inout GraphTransaction) throws {
        try body(&transaction)
    }
}

@Suite("Floating topics, summaries and images in the graph")
struct NodeTypeGraphTests {
    static let bytes = Data(repeating: 7, count: 64)

    static func fixture() throws -> GraphFixture {
        try GraphFixture("""
        Root
          A
          B
          C
          S
        """)
    }

    // MARK: Floating topics

    @Test func floatingTopicIsValidAndUndoable() throws {
        var fixture = try Self.fixture()
        let mapID = fixture.state.map.id
        let floating = MindNode(mapID: mapID, parentID: nil, title: "Idea", position: TopicPosition(x: 320, y: -40))

        try fixture.engine.execute(EditForTest { try $0.insertNode(floating) })

        #expect(fixture.state.floatingTopicIDs == [floating.id])
        #expect(GraphValidator.validate(fixture.state).isEmpty)
        #expect(try GraphRepair.repair(fixture.state, now: .now).changes.isEmpty)
        fixture.engine.undo()
        #expect(fixture.state.node(floating.id) == nil)
        fixture.engine.redo()
        #expect(fixture.state.node(floating.id)?.position == TopicPosition(x: 320, y: -40))
    }

    /// Children of a floating topic are reachable through it.
    @Test func floatingTopicChildrenAreNotDetached() throws {
        var fixture = try Self.fixture()
        let mapID = fixture.state.map.id
        let floating = MindNode(mapID: mapID, parentID: nil, title: "Idea", position: TopicPosition(x: 0, y: 200))
        let child = MindNode(mapID: mapID, parentID: floating.id, title: "Detail")
        try fixture.engine.execute(EditForTest { try $0.insertNode(floating); try $0.insertNode(child) })

        #expect(GraphValidator.validate(fixture.state).isEmpty)
    }

    @Test func attachingAFloatingTopicClearsItsPosition() throws {
        var fixture = try Self.fixture()
        let rootID = fixture["Root"]
        let floating = MindNode(mapID: fixture.state.map.id, parentID: nil, title: "Idea", sortOrder: 10, position: TopicPosition(x: 5, y: 5))
        try fixture.engine.execute(EditForTest { try $0.insertNode(floating) })

        try fixture.engine.execute(EditForTest { try $0.updateNode(floating.id) { $0.parentID = rootID } })

        #expect(fixture.state.node(floating.id)?.position == nil)
        #expect(fixture.state.floatingTopicIDs.isEmpty)
        fixture.engine.undo()
        #expect(fixture.state.node(floating.id)?.position == TopicPosition(x: 5, y: 5))
        fixture.engine.redo()
        #expect(fixture.state.node(floating.id)?.parentID == rootID)
        #expect(fixture.state.node(floating.id)?.position == nil)
    }

    /// The tree wins: a position on a topic with a parent, or on the root, goes.
    @Test func repairClearsStrayPositions() throws {
        let fixture = try Self.fixture()
        var nodes = fixture.state.nodes
        nodes[fixture["A"]]?.position = TopicPosition(x: 1, y: 2)
        nodes[fixture["Root"]]?.position = TopicPosition(x: 3, y: 4)
        let stored = GraphState(map: fixture.state.map, nodes: nodes.values, edges: [])

        #expect(GraphValidator.validate(stored) == [.strayPosition(fixture["A"]), .strayPosition(fixture["Root"])])
        let result = try GraphRepair.repair(stored, now: .now)

        #expect(GraphValidator.validate(result.state).isEmpty)
        #expect(result.state.nodes.values.allSatisfy { $0.position == nil })
        #expect(Set(result.changes.savedNodes.map(\.id)) == [fixture["A"], fixture["Root"]])
    }

    /// A parentless topic without a position is still a detached branch; one
    /// whose parent is gone is re-attached and loses its position.
    @Test func detachedBranchesAreReattachedWithoutPosition() throws {
        let fixture = try Self.fixture()
        let mapID = fixture.state.map.id
        let loose = MindNode(mapID: mapID, parentID: nil, title: "Loose")
        let orphan = MindNode(mapID: mapID, parentID: NodeID(), title: "Orphan", position: TopicPosition(x: 9, y: 9))
        let floating = MindNode(mapID: mapID, parentID: nil, title: "Floating", position: TopicPosition(x: 1, y: 1))
        let stored = GraphState(map: fixture.state.map, nodes: Array(fixture.state.nodes.values) + [loose, orphan, floating], edges: [])

        let result = try GraphRepair.repair(stored, now: .now)

        let rootID = fixture["Root"]
        #expect(result.state.node(loose.id)?.parentID == rootID)
        #expect(result.state.node(orphan.id)?.parentID == rootID)
        #expect(result.state.node(orphan.id)?.position == nil)
        #expect(result.state.node(floating.id)?.parentID == nil)
        #expect(result.state.floatingTopicIDs == [floating.id])
    }

    /// With the root gone, a plain parentless topic becomes the root before a
    /// floating topic does, even an older one.
    @Test func newRootPrefersTopicsWithoutPosition() throws {
        let mapID = MapID()
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let floating = MindNode(mapID: mapID, parentID: nil, title: "Floating", createdAt: start, position: TopicPosition(x: 1, y: 1))
        let plain = MindNode(mapID: mapID, parentID: nil, title: "Plain", createdAt: start.addingTimeInterval(5))
        let stored = GraphState(map: MindMap(id: mapID, title: "Lost root"), nodes: [floating, plain], edges: [])

        let first = try GraphRepair.repair(stored, now: start.addingTimeInterval(10))
        let second = try GraphRepair.repair(stored, now: start.addingTimeInterval(10))

        #expect(first.state.map.rootNodeID == plain.id)
        #expect(first.state.floatingTopicIDs == [floating.id])
        #expect(first.state == second.state)
    }

    @Test func onlyFloatingTopicsLeftMakesTheOldestTheRoot() throws {
        let mapID = MapID()
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let older = MindNode(mapID: mapID, parentID: nil, title: "Older", createdAt: start, position: TopicPosition(x: 1, y: 1))
        let newer = MindNode(mapID: mapID, parentID: nil, title: "Newer", createdAt: start.addingTimeInterval(1), position: TopicPosition(x: 2, y: 2))
        let stored = GraphState(map: MindMap(id: mapID, title: "Lost root"), nodes: [older, newer], edges: [])

        let result = try GraphRepair.repair(stored, now: start.addingTimeInterval(10))

        #expect(result.state.map.rootNodeID == older.id)
        #expect(result.state.root?.position == nil)
        #expect(result.state.floatingTopicIDs == [newer.id])
        #expect(GraphValidator.validate(result.state).isEmpty)
    }

    // MARK: Summaries

    static func summary(_ fixture: GraphFixture, first: String = "A", last: String = "B", topic: String = "S", at date: Date? = nil) -> MindGroup {
        MindGroup(
            mapID: fixture.state.map.id, kind: .summary, parentNodeID: fixture["Root"],
            firstNodeID: fixture[first], lastNodeID: fixture[last], createdAt: date ?? fixture.state.map.createdAt,
            summaryNodeID: fixture[topic]
        )
    }

    @Test func summaryTopicIsLeftOutOfSiblingRuns() throws {
        var fixture = try Self.fixture()
        let summary = Self.summary(fixture, first: "A", last: "C")
        try fixture.engine.execute(EditForTest { try $0.insertGroup(summary) })

        let rootID = fixture["Root"]
        #expect(fixture.state.runSiblingIDs(of: rootID) == [fixture["A"], fixture["B"], fixture["C"]])
        #expect(fixture.state.childIDs(of: rootID).contains(fixture["S"]))
        #expect(fixture.state.members(of: summary) == [fixture["A"], fixture["B"], fixture["C"]])
        // A boundary cannot end on the summary topic.
        let boundary = MindGroup(mapID: fixture.state.map.id, parentNodeID: rootID, firstNodeID: fixture["C"], lastNodeID: fixture["S"])
        #expect(fixture.state.members(of: boundary) == nil)
    }

    @Test func deletingTheSummaryTopicRemovesItsSummary() throws {
        var fixture = try Self.fixture()
        let summary = Self.summary(fixture)
        try fixture.engine.execute(EditForTest { try $0.insertGroup(summary) })

        let summaryTopic = fixture["S"]
        let changes = try fixture.engine.execute(EditForTest { try $0.removeNode(summaryTopic) })

        #expect(changes.deletedGroupIDs == [summary.id])
        #expect(fixture.state.groups.isEmpty)
        fixture.engine.undo()
        #expect(fixture.state.group(summary.id) == summary)
        #expect(fixture.state.node(fixture["S"]) != nil)
        fixture.engine.redo()
        #expect(fixture.state.groups.isEmpty)
    }

    /// Moving the summary topic elsewhere keeps it where the tree puts it.
    @Test func movingTheSummaryTopicAwayRemovesItsSummary() throws {
        var fixture = try Self.fixture()
        let summary = Self.summary(fixture)
        try fixture.engine.execute(EditForTest { try $0.insertGroup(summary) })
        let newParent = fixture["C"]

        let summaryTopic = fixture["S"]
        try fixture.engine.execute(EditForTest { try $0.updateNode(summaryTopic) { $0.parentID = newParent } })

        #expect(fixture.state.groups.isEmpty)
        fixture.engine.undo()
        #expect(fixture.state.group(summary.id) == summary)
        fixture.engine.redo()
        #expect(fixture.state.node(fixture["S"])?.parentID == newParent)
        #expect(fixture.state.groups.isEmpty)
    }

    @Test func deletingAnEndShrinksTheSummary() throws {
        var fixture = try Self.fixture()
        let summary = Self.summary(fixture)
        try fixture.engine.execute(EditForTest { try $0.insertGroup(summary) })

        let a = fixture["A"]
        try fixture.engine.execute(EditForTest { try $0.removeNode(a) })

        #expect(fixture.state.group(summary.id)?.firstNodeID == fixture["B"])
        #expect(fixture.state.group(summary.id)?.summaryNodeID == fixture["S"])
        fixture.engine.undo()
        #expect(fixture.state.group(summary.id)?.firstNodeID == fixture["A"])
    }

    @Test func repairDeletesSummariesThatCannotNameTheirTopic() throws {
        let fixture = try Self.fixture()
        let start = fixture.state.map.createdAt
        let oldest = Self.summary(fixture, at: start)
        let second = Self.summary(fixture, first: "C", last: "C", at: start.addingTimeInterval(1))
        var unnamed = Self.summary(fixture, first: "C", last: "C", at: start.addingTimeInterval(2))
        unnamed.summaryNodeID = nil
        var misplaced = Self.summary(fixture, first: "B", last: "C", topic: "A", at: start.addingTimeInterval(3))
        misplaced.parentNodeID = fixture["B"]
        let stored = GraphState(
            map: fixture.state.map, nodes: fixture.state.nodes.values, edges: [],
            groups: [oldest, second, unnamed, misplaced]
        )

        let issues = GraphValidator.validate(stored)
        #expect(issues.contains(.invalidSummary(second.id)))
        #expect(issues.contains(.invalidSummary(misplaced.id)))
        #expect(issues.contains(.invalidSummary(unnamed.id)))
        let first = try GraphRepair.repair(stored, now: start.addingTimeInterval(10))
        let again = try GraphRepair.repair(stored, now: start.addingTimeInterval(10))

        #expect(first.state == again.state)
        #expect(GraphValidator.validate(first.state).isEmpty)
        #expect(first.state.group(oldest.id) == oldest)
        #expect(first.state.group(second.id) == nil)
        #expect(first.state.group(misplaced.id) == nil)
        #expect(first.state.group(unnamed.id) == nil)
        // Repair never deletes a topic.
        #expect(first.state.nodes.count == stored.nodes.count)
    }

    /// The summary topic may still be syncing; the bracket waits for it.
    @Test func summaryWaitsForItsTopicUntilItExpires() throws {
        let fixture = try Self.fixture()
        let start = fixture.state.map.createdAt
        var waiting = Self.summary(fixture, at: start)
        waiting.summaryNodeID = NodeID()
        let stored = GraphState(map: fixture.state.map, nodes: fixture.state.nodes.values, edges: [], groups: [waiting])

        #expect(GraphValidator.validate(stored).isEmpty)
        #expect(try GraphRepair.repair(stored, now: start.addingTimeInterval(60)).changes.isEmpty)
        let expired = try GraphRepair.repair(stored, now: start.addingTimeInterval(GraphRepair.orphanLifetime + 1))
        #expect(expired.changes.deletedGroupIDs == [waiting.id])
    }

    /// The copy's summary names the copy's summary topic, and links and callouts come along.
    @Test func duplicatingABranchCopiesItsSummaryLinkAndCallout() throws {
        var fixture = try GraphFixture("""
        Root
          Plan
            A
            B
            S
        """)
        let summary = MindGroup(
            mapID: fixture.state.map.id, kind: .summary, parentNodeID: fixture["Plan"],
            firstNodeID: fixture["A"], lastNodeID: fixture["B"], summaryNodeID: fixture["S"]
        )
        let a = fixture["A"]
        try fixture.engine.execute(EditForTest { transaction in
            try transaction.insertGroup(summary)
            try transaction.updateNode(a) { node in
                node.link = TopicLink(string: "https://example.com")
                node.callout = "Note"
            }
        })
        let copyID = NodeID()

        try fixture.engine.execute(DuplicateBranchCommand(nodeID: fixture["Plan"], copyID: copyID))

        let copied = try #require(fixture.state.groups(under: copyID).first)
        #expect(copied.kind == .summary)
        #expect(copied.summaryNodeID.flatMap { fixture.state.node($0)?.title } == "S")
        #expect(copied.summaryNodeID != fixture["S"])
        let copiedA = try #require(fixture.state.children(of: copyID).first { $0.title == "A" })
        #expect(copiedA.link == TopicLink(string: "https://example.com"))
        #expect(copiedA.callout == "Note")
        fixture.engine.undo()
        #expect(fixture.state.node(copyID) == nil)
        fixture.engine.redo()
        #expect(fixture.state.groups(under: copyID).count == 1)
    }

    @Test func aBoundaryCannotEndOnASummaryTopic() throws {
        var fixture = try Self.fixture()
        let summary = Self.summary(fixture)
        try fixture.engine.execute(EditForTest { try $0.insertGroup(summary) })

        #expect(throws: GraphError.notSiblings(fixture["S"])) {
            try fixture.engine.execute(AddGroupCommand(from: fixture["C"], to: fixture["S"]))
        }
    }

    // MARK: Images

    static func image(on nodeID: NodeID, in fixture: GraphFixture, at date: Date? = nil) -> MindImage {
        MindImage(
            mapID: fixture.state.map.id, nodeID: nodeID, data: bytes, uniformType: "public.png",
            pixelWidth: 40, pixelHeight: 30, byteCount: bytes.count, createdAt: date ?? .now
        )
    }

    @Test func addedImageKeepsBytesInTheChangeOnly() throws {
        var fixture = try Self.fixture()
        let image = Self.image(on: fixture["A"], in: fixture)

        let changes = try fixture.engine.execute(EditForTest { try $0.insertImage(image) })

        #expect(changes.savedImages.map(\.data) == [Self.bytes])
        #expect(fixture.state.image(of: fixture["A"])?.data == nil)
        let undoneResult = fixture.engine.undo()
        let undone = try #require(undoneResult)
        #expect(fixture.state.images.isEmpty)
        #expect(undone.deletedImageIDs == [image.id])
        let redoneResult = fixture.engine.redo()
        let redone = try #require(redoneResult)
        #expect(redone.savedImages.map(\.data) == [Self.bytes])
        #expect(fixture.state.image(of: fixture["A"])?.id == image.id)
    }

    @Test func oneImagePerTopic() throws {
        var fixture = try Self.fixture()
        let first = Self.image(on: fixture["A"], in: fixture)
        try fixture.engine.execute(EditForTest { try $0.insertImage(first) })
        let second = Self.image(on: fixture["A"], in: fixture)

        #expect(throws: GraphError.nodeHasImage(first.id)) {
            try fixture.engine.execute(EditForTest { try $0.insertImage(second) })
        }
    }

    /// A size edit in the same step as the add still saves the bytes; a later
    /// one carries none, so the stored file is left alone.
    @Test func editingAnImageNeverDropsOrRewritesItsBytes() throws {
        var fixture = try Self.fixture()
        let image = Self.image(on: fixture["A"], in: fixture)
        let added = try fixture.engine.execute(EditForTest {
            try $0.insertImage(image)
            try $0.updateImage(image.id) { $0.displayWidth = 96 }
        })
        #expect(added.savedImages.first?.data == Self.bytes)
        #expect(added.savedImages.first?.displayWidth == 96)

        let edited = try fixture.engine.execute(EditForTest { try $0.updateImage(image.id) { $0.altText = "Sketch" } })

        #expect(edited.savedImages.map(\.data) == [nil])
        fixture.engine.undo()
        #expect(fixture.state.images[image.id]?.altText == nil)
        fixture.engine.redo()
        #expect(fixture.state.images[image.id]?.altText == "Sketch")
    }

    /// Deleting the topic deletes its image; with the bytes loaded, undo has them.
    @Test func deletingATopicRemovesItsImageAndUndoRestoresTheBytes() throws {
        var fixture = try Self.fixture()
        let image = Self.image(on: fixture["A"], in: fixture)
        try fixture.engine.execute(EditForTest { try $0.insertImage(image) })
        fixture.engine.imageData = [image.id: Self.bytes]

        let a = fixture["A"]
        let deleted = try fixture.engine.execute(EditForTest { try $0.removeNode(a) })

        #expect(deleted.deletedImageIDs == [image.id])
        #expect(fixture.state.images.isEmpty)
        let undoneResult = fixture.engine.undo()
        let undone = try #require(undoneResult)
        #expect(undone.savedImages.map(\.data) == [Self.bytes])
        #expect(fixture.state.image(of: fixture["A"])?.id == image.id)
        fixture.engine.redo()
        #expect(fixture.state.images.isEmpty)
    }

    @Test func repairDeletesDanglingAndDuplicateImagesKeepingTheNewest() throws {
        let fixture = try Self.fixture()
        let start = fixture.state.map.createdAt
        let dangling = Self.image(on: NodeID(), in: fixture, at: start)
        let older = Self.image(on: fixture["A"], in: fixture, at: start)
        let newer = Self.image(on: fixture["A"], in: fixture, at: start.addingTimeInterval(1))
        let stored = GraphState(
            map: fixture.state.map, nodes: fixture.state.nodes.values, edges: [], images: [dangling, older, newer]
        )

        #expect(GraphValidator.validate(stored) == [.danglingImage(dangling.id), .duplicateImage(older.id)])
        let first = try GraphRepair.repair(stored, now: start.addingTimeInterval(10))
        let again = try GraphRepair.repair(stored, now: start.addingTimeInterval(10))

        #expect(first.state == again.state)
        #expect(Set(first.changes.deletedImageIDs) == [dangling.id, older.id])
        #expect(first.state.images.keys.sorted() == [newer.id])
        #expect(stored.images.values.allSatisfy { $0.data == nil })
    }
}

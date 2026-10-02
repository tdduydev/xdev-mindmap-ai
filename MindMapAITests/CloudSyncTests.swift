import CloudKit
import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import Testing

/// An open map taking in writes from outside its repository, as iCloud
/// imports arrive (FR-SYN-04), and the window's undo after them (FR-UND-05).
@Suite("Changes from iCloud in an open map", .timeLimit(.minutes(1)))
struct StoredChangeSessionTests {
    let folder: URL
    let repository: SwiftDataMapRepository
    /// Another writer on the same file: what CloudKit's import looks like to the app.
    let outside: SwiftDataMapRepository
    let mapID: MapID
    let rootID: NodeID
    /// The window's; the session holds it weakly.
    let undoManager = UndoManager()

    init() async throws {
        undoManager.groupsByEvent = false
        folder = FileManager.default.temporaryDirectory.appending(path: "CloudSyncTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "MindMapAI.store")
        repository = try PersistenceController.makeRepository(at: .file(url))
        outside = try PersistenceController.makeRepository(at: .file(url))
        let graph = GraphState.newMap(title: "Trip")
        try await repository.create(graph)
        mapID = graph.map.id
        rootID = try #require(graph.map.rootNodeID)
    }

    private func open() async throws -> EditorSession {
        guard case .ready(let session) = await EditorSession.open(mapID: mapID, repository: repository, onMapChange: { _ in }) else {
            throw OpenFailed()
        }
        session.undoManager = undoManager
        return session
    }

    /// One named step, grouped as a menu event would group it.
    private func step(_ session: EditorSession, _ intent: () -> Void) {
        undoManager.beginUndoGrouping()
        intent()
        undoManager.endUndoGrouping()
    }

    private func editOutside(_ command: (GraphState) throws -> any GraphCommand) async throws {
        let stored = try #require(try await outside.loadGraph(for: mapID))
        var engine = try GraphEngine(state: stored)
        let changes = try engine.execute(command(stored))
        try await outside.save(changes, map: engine.state.map)
    }

    private func node(titled title: String, in session: EditorSession) -> NodeID? {
        session.engine.state.nodes.values.first { $0.title == title }?.id
    }

    @Test func anOutsideEditShowsInTheOpenMap() async throws {
        let session = try await open()
        let added = NodeID()

        try await editOutside { _ in AddNodeCommand(nodeID: added, .child(of: rootID), title: "From iPad") }
        await session.takeStoredChanges()

        #expect(session.engine.state.node(added)?.title == "From iPad")
        #expect(session.rows.map(\.node.title) == ["Trip", "From iPad"])
    }

    @Test func pendingLocalEditsAreNotMistakenForOutsideOnes() async throws {
        let session = try await open()
        step(session) { session.addChild() }
        let local = try #require(session.selection)
        step(session) { session.rename(local, to: "Local") }

        try await editOutside { _ in AddNodeCommand(.child(of: rootID), title: "Remote") }
        await session.takeStoredChanges()

        #expect(session.engine.state.node(local)?.title == "Local")
        #expect(node(titled: "Remote", in: session) != nil)
        #expect(undoManager.undoActionName == "Rename Topic")
    }

    @Test func undoKeepsOnlyStepsTheOutsideChangeDidNotTouch() async throws {
        let session = try await open()
        step(session) { session.addChild() }
        let first = try #require(session.selection)
        step(session) { session.rename(first, to: "Flights") }
        step(session) { session.renameMap(to: "Summer Trip") }
        await session.flush()

        try await editOutside { _ in UpdateNodeCommand(nodeID: first, .title("Trains")) }
        await session.takeStoredChanges()

        #expect(session.engine.state.node(first)?.title == "Trains")
        #expect(session.engine.undoStepNames.count == 1)
        #expect(undoManager.undoActionName == "Rename Map")
        #expect(!undoManager.canRedo)

        undoManager.undo()
        #expect(session.map.title == "Trip")
        #expect(session.engine.state.node(first)?.title == "Trains")
        #expect(!undoManager.canUndo)
        undoManager.redo()
        #expect(session.map.title == "Summer Trip")
        #expect(session.engine.state.node(first)?.title == "Trains")
    }

    @Test func aMapDeletedElsewhereStopsTheEditor() async throws {
        let session = try await open()

        try await outside.deleteMap(mapID)
        await session.takeStoredChanges()

        #expect(session.removedElsewhere == .deleted)
    }

    @Test func aMapMovedToRecentlyDeletedElsewhereStopsTheEditor() async throws {
        let session = try await open()

        try await outside.moveToRecentlyDeleted(mapID, at: .now)
        await session.takeStoredChanges()

        #expect(session.removedElsewhere == .recentlyDeleted)
    }

    private struct OpenFailed: Error {}

    @Test func theStoreStreamDrivesIt() async throws {
        let session = try await open()
        let observing = Task { await session.observeStore() }
        defer { observing.cancel() }
        // Let the observer subscribe before the outside write.
        try await Task.sleep(for: .milliseconds(100))

        try await editOutside { _ in AddNodeCommand(.child(of: rootID), title: "Streamed") }
        while node(titled: "Streamed", in: session) == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

@Suite("Sync monitor")
struct CloudSyncMonitorTests {
    let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: "CloudSyncMonitorTests-\(UUID().uuidString)"))
    }

    @Test func aBuildWithoutTheEntitlementNeverMirrors() {
        let monitor = CloudSyncMonitor(defaults: defaults, isEntitled: false, isUITest: false)
        #expect(monitor.storeSync == .off)
        #expect(!monitor.needsRelaunch)
    }

    @Test func syncIsOnByDefaultWhenEntitled() {
        let monitor = CloudSyncMonitor(defaults: defaults, isEntitled: true, isUITest: false)
        #expect(monitor.storeSync == .appContainer)
    }

    @Test func uiTestsNeverReachICloud() {
        let monitor = CloudSyncMonitor(defaults: defaults, isEntitled: true, isUITest: true)
        #expect(monitor.storeSync == .off)
    }

    @Test func turningItOffIsKeptAndAppliesAtNextLaunch() {
        let monitor = CloudSyncMonitor(defaults: defaults, isEntitled: true, isUITest: false)
        monitor.setEnabled(false)

        #expect(!monitor.isEnabled)
        #expect(CloudSyncMonitor(defaults: defaults, isEntitled: true, isUITest: false).storeSync == .off)
    }

    @Test func cloudKitErrorsMapToWhatThePersonNeeds() {
        #expect(CloudSyncMonitor.failure(code: .networkUnavailable) == .network)
        #expect(CloudSyncMonitor.failure(code: .quotaExceeded) == .quotaExceeded)
        #expect(CloudSyncMonitor.failure(code: .partialFailure, partialCodes: [.quotaExceeded]) == .quotaExceeded)
        #expect(CloudSyncMonitor.failure(code: .notAuthenticated) == .notAuthenticated)
        #expect(CloudSyncMonitor.failure(code: .serverRejectedRequest) == .other)
        #expect(CloudSyncMonitor.failure(code: nil) == .other)
    }

    @Test func everyStateHasWords() {
        let states: [CloudSyncState] = [
            .off, .unavailable, .notSignedIn, .restricted, .accountNeedsAttention,
            .waitingForNetwork, .syncing, .upToDate, .error(.quotaExceeded), .error(.other),
        ]
        for state in states {
            #expect(!state.title.isEmpty)
            #expect(!state.detail.isEmpty)
        }
    }
}

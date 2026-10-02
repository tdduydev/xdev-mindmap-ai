import Foundation
import MindMapDomain
import MindMapGraph
@testable import MindMapPersistence
import Testing

/// The store moves from the app's own container into the App Group (MM-11),
/// so the Share Extension and the app read the same maps.
@Suite("App Group store")
struct AppGroupStoreTests {
    let root: URL

    init() throws {
        root = URL.temporaryDirectory.appending(path: "AppGroupStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    @Test func storeLivesUnderTheGroupContainer() {
        let container = URL(filePath: "/tmp/group", directoryHint: .isDirectory)
        #expect(AppGroup.storeURL(in: container).path(percentEncoded: false) == "/tmp/group/Library/Application Support/MindMapAI.store")
    }

    @Test func movedStoreOpensWithEveryMap() async throws {
        let legacy = root.appending(path: "App/Application Support/MindMapAI.store")
        let shared = AppGroup.storeURL(in: root.appending(path: "Group", directoryHint: .isDirectory))
        let graph = try Self.graph(title: "Kế hoạch")
        try await Self.write(graph, to: legacy)

        let outcome = try StoreRelocation.move(from: legacy, to: shared)

        #expect(outcome == .moved)
        #expect(!FileManager.default.fileExists(atPath: legacy.path(percentEncoded: false)))
        let reopened = try PersistenceController.makeRepository(at: .file(shared))
        #expect(try await reopened.loadGraph(for: graph.map.id) == graph)
    }

    @Test func existingSharedStoreIsNeverReplaced() async throws {
        let legacy = root.appending(path: "App/MindMapAI.store")
        let shared = root.appending(path: "Group/MindMapAI.store")
        let old = try Self.graph(title: "Old")
        let new = try Self.graph(title: "New")
        try await Self.write(old, to: legacy)
        try await Self.write(new, to: shared)

        #expect(try StoreRelocation.move(from: legacy, to: shared) == .destinationExists)

        let legacyMaps = try await PersistenceController.makeRepository(at: .file(legacy)).fetchMaps()
        let sharedMaps = try await PersistenceController.makeRepository(at: .file(shared)).fetchMaps()
        #expect(legacyMaps.map(\.id) == [old.map.id])
        #expect(sharedMaps.map(\.id) == [new.map.id])
    }

    @Test func nothingToMoveOnAFreshInstall() throws {
        let outcome = try StoreRelocation.move(from: root.appending(path: "none.store"), to: root.appending(path: "Group/MindMapAI.store"))
        #expect(outcome == .nothingToMove)
    }

    @Test func extensionSeesTheStoreOnlyAfterTheAppMadeIt() async throws {
        let container = root.appending(path: "Group", directoryHint: .isDirectory)
        #expect(!AppGroup.hasStore(in: container))

        try await Self.write(try Self.graph(title: "Plan"), to: AppGroup.storeURL(in: container))

        #expect(AppGroup.hasStore(in: container))
    }

    private static func graph(title: String) throws -> GraphState {
        var engine = try GraphEngine(state: GraphState.newMap(title: title))
        let rootID = try #require(engine.state.map.rootNodeID)
        try engine.execute(AddNodeCommand(.child(of: rootID), title: "Topic"))
        return engine.state
    }

    /// Writes through a repository that is gone when this returns, as the
    /// previous launch of the app would have.
    private static func write(_ graph: GraphState, to url: URL) async throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let repository = try PersistenceController.makeRepository(at: .file(url))
        try await repository.create(graph)
    }
}

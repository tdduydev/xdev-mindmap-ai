import Foundation
import MindMapDomain
@testable import MindMapPersistence
import SwiftData
import Testing

@Suite("Migration harness")
struct MigrationHarnessTests {
    static let mapID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    static let rootID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    static let childID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!

    @Test func currentPlanOpensShippedV1Store() async throws {
        let fixture = try #require(Bundle.module.url(forResource: "V1", withExtension: "store"))
        let folder = FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "map.store")
        try FileManager.default.copyItem(at: fixture, to: url)

        let repository = try PersistenceController.makeRepository(at: .file(url))
        let graph = try #require(try await repository.loadGraph(for: MapID(Self.mapID)))
        #expect(graph.map.title == "V1 fixture")
        #expect(graph.map.rootNodeID == NodeID(Self.rootID))
        #expect(graph.nodes.count == 2)
        #expect(graph.node(NodeID(Self.childID))?.parentID == NodeID(Self.rootID))
        #expect(graph.node(NodeID(Self.childID))?.note == "Migration keeps notes")
    }

    /// Run with MM2_FIXTURE_OUTPUT=/private/tmp/V1.store, then checkpoint the
    /// SQLite file and copy it into Fixtures. This deliberately opens V1 alone.
    @Test func generateV1FixtureWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["MM2_FIXTURE_OUTPUT"] else { return }
        let url = URL(fileURLWithPath: path)
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration("V1Fixture", schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = ModelContext(container)
        let instant = Date(timeIntervalSinceReferenceDate: 1_000)
        let map = MapRecord(mapID: Self.mapID)
        map.title = "V1 fixture"
        map.rootNodeID = Self.rootID
        map.createdAt = instant
        map.updatedAt = instant
        let root = NodeRecord(nodeID: Self.rootID, mapID: Self.mapID)
        root.title = "V1 fixture"
        root.createdAt = instant
        root.updatedAt = instant
        let child = NodeRecord(nodeID: Self.childID, mapID: Self.mapID)
        child.parentID = Self.rootID
        child.title = "Child"
        child.note = "Migration keeps notes"
        child.createdAt = instant
        child.updatedAt = instant
        context.insert(map)
        context.insert(root)
        context.insert(child)
        try context.save()
    }
}

import Foundation
import MindMapDomain
import MindMapGraph
@testable import MindMapPersistence
import SwiftData
import Testing

/// Opens stores written by shipped schemas with today's migration plan, the
/// way an app update opens a user's library. A new schema adds its stage to
/// `MindMapMigrationPlan` and its own expectations here; these tests keep
/// opening the V1 store through every stage, unchanged.
@Suite("Migration harness")
struct MigrationHarnessTests {
    @Test func currentPlanOpensTheV1Store() async throws {
        let store = try FixtureStore(copying: "V1")
        defer { store.remove() }

        let repository = try PersistenceController.makeRepository(at: .file(store.url))

        #expect(try await repository.fetchMaps() == [V1Fixture.graph.map])
        #expect(try await repository.loadGraph(for: V1Fixture.mapID) == V1Fixture.graph)
    }

    /// The plan is `[SchemaV1, SchemaV2]`: V1's data comes through with every
    /// value, every V2 field is empty (so maps draw as before), and there are
    /// no tags, tag links, boundaries, summaries or images yet.
    @Test func v1StoreOpensAsV2WithEmptyNewFields() async throws {
        let store = try FixtureStore(copying: "V1")
        defer { store.remove() }
        let container = try PersistenceController.makeContainer(at: .file(store.url))
        #expect(container.schema.version == SchemaV2.versionIdentifier)

        let context = ModelContext(container)
        let maps = try context.fetch(FetchDescriptor<MapRecord>())
        #expect(maps.map(\.mapID) == [V1Fixture.mapID.rawValue])
        #expect(maps.allSatisfy { $0.deletedAt == nil })
        let nodes = try context.fetch(FetchDescriptor<NodeRecord>())
        #expect(nodes.count == 3)
        for node in nodes {
            #expect(node.colorToken == nil && node.symbol == nil && node.taskStateRaw == nil)
            #expect(node.priority == nil && node.startDate == nil && node.dueDate == nil)
            #expect(node.linkURL == nil && node.positionX == nil && node.positionY == nil && node.calloutText == nil)
        }
        let edges = try context.fetch(FetchDescriptor<EdgeRecord>())
        #expect(edges.map(\.label) == ["cites"])
        #expect(edges.allSatisfy { $0.lineStyleRaw == nil && $0.arrowHeadsRaw == nil && $0.colorToken == nil })
        #expect(try context.fetchCount(FetchDescriptor<TagRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<NodeTagRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<GroupRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ImageRecord>()) == 0)

        let graph = try #require(try await SwiftDataMapRepository(modelContainer: container).loadGraph(for: V1Fixture.mapID))
        #expect(graph == V1Fixture.graph)
        #expect(try GraphRepair.repair(graph, now: .now).changes.isEmpty)
    }

    /// A migrated V1 map takes the new records and keeps them.
    @Test func migratedStoreKeepsOrganization() async throws {
        let store = try FixtureStore(copying: "V1")
        defer { store.remove() }
        let repository = try PersistenceController.makeRepository(at: .file(store.url))
        var engine = try GraphEngine(state: try #require(try await repository.loadGraph(for: V1Fixture.mapID)))

        let changes = try engine.execute(BatchCommand([
            TagNodesCommand(nodeIDs: [V1Fixture.childID], add: [.named("Việc")]),
            SetTaskCommand(nodeIDs: [V1Fixture.siblingID], state: .set(.open), due: .set(CalendarDay(isoString: "2026-12-31"))),
            AddGroupCommand(from: V1Fixture.childID, to: V1Fixture.siblingID, title: "Both"),
        ]))
        try await repository.save(changes, map: engine.state.map)

        let reopened = try PersistenceController.makeRepository(at: .file(store.url))
        #expect(try await reopened.loadGraph(for: V1Fixture.mapID) == engine.state)
    }

    /// A migrated V1 map takes every node type of MM-59 and keeps it on reopening,
    /// the image's bytes included.
    @Test func migratedStoreKeepsNodeTypes() async throws {
        let store = try FixtureStore(copying: "V1")
        defer { store.remove() }
        let repository = try PersistenceController.makeRepository(at: .file(store.url))
        var engine = try GraphEngine(state: try #require(try await repository.loadGraph(for: V1Fixture.mapID)))
        let bytes = Data((0..<255).map(UInt8.init))
        let floating = MindNode(mapID: V1Fixture.mapID, parentID: nil, title: "Floating", position: TopicPosition(x: -120.5, y: 64))
        let summaryTopic = MindNode(mapID: V1Fixture.mapID, parentID: V1Fixture.rootID, title: "Summary", sortOrder: 3)
        let summary = MindGroup(
            mapID: V1Fixture.mapID, kind: .summary, parentNodeID: V1Fixture.rootID,
            firstNodeID: V1Fixture.childID, lastNodeID: V1Fixture.siblingID, summaryNodeID: summaryTopic.id
        )
        let image = MindImage(
            mapID: V1Fixture.mapID, nodeID: V1Fixture.childID, data: bytes, uniformType: "public.png",
            pixelWidth: 16, pixelHeight: 9, byteCount: bytes.count, displayWidth: 240, altText: "Whiteboard"
        )

        let changes = try engine.execute(EditGraphForTest { transaction in
            try transaction.insertNode(floating)
            try transaction.insertNode(summaryTopic)
            try transaction.insertGroup(summary)
            try transaction.insertImage(image)
            try transaction.updateNode(V1Fixture.siblingID) { node in
                node.link = TopicLink.normalized("example.com/plan")
                node.callout = MindNode.normalizedCallout("Check the budget")
            }
        })
        try await repository.save(changes, map: engine.state.map)

        let reopened = try PersistenceController.makeRepository(at: .file(store.url))
        let loaded = try #require(try await reopened.loadGraph(for: V1Fixture.mapID))
        #expect(loaded == engine.state)
        #expect(loaded.node(V1Fixture.siblingID)?.link?.string == "https://example.com/plan")
        #expect(loaded.node(V1Fixture.siblingID)?.callout == "Check the budget")
        #expect(loaded.floatingTopicIDs == [floating.id])
        #expect(loaded.group(summary.id)?.summaryNodeID == summaryTopic.id)
        #expect(loaded.image(of: V1Fixture.childID)?.altText == "Whiteboard")
        #expect(try await reopened.imageData(for: image.id) == bytes)
        #expect(try GraphRepair.repair(loaded, now: .now).changes.isEmpty)
    }

    /// Opening is not enough: the migrated store must take edits and keep them.
    @Test func migratedStoreKeepsNewEdits() async throws {
        let store = try FixtureStore(copying: "V1")
        defer { store.remove() }
        let repository = try PersistenceController.makeRepository(at: .file(store.url))
        let stored = try #require(try await repository.loadGraph(for: V1Fixture.mapID))
        var engine = try GraphEngine(state: stored)

        let changes = try engine.execute(AddNodeCommand(.child(of: V1Fixture.rootID), title: "Added after migration"))
        try await repository.save(changes, map: engine.state.map)

        let reopened = try PersistenceController.makeRepository(at: .file(store.url))
        #expect(try await reopened.loadGraph(for: V1Fixture.mapID) == engine.state)
    }

    /// Catches a schema added to the app but not to the plan, or the reverse.
    @Test func planEndsAtTheSchemaTheAppOpens() throws {
        let versions = MindMapMigrationPlan.schemas.map { $0.versionIdentifier }
        #expect(versions == versions.sorted())
        #expect(Set(versions).count == versions.count)
        #expect(MindMapMigrationPlan.stages.count == versions.count - 1)

        let container = try PersistenceController.makeContainer(at: .inMemory)
        #expect(container.schema.version == versions.last)
    }

    /// Writes `Fixtures/V1.store`. It runs only when asked, because the
    /// checked-in fixture must stay what V1 wrote; see docs/data-model.md.
    @Test(.enabled(if: V1Fixture.outputPath != nil))
    func writeV1Fixture() throws {
        let url = URL(fileURLWithPath: try #require(V1Fixture.outputPath))
        try V1Fixture.write(to: url)
    }
}

/// Runs primitives directly; the user commands for the node types come with MM-60 to MM-66.
struct EditGraphForTest: GraphCommand {
    let body: @Sendable (inout GraphTransaction) throws -> Void

    init(_ body: @escaping @Sendable (inout GraphTransaction) throws -> Void) {
        self.body = body
    }

    func execute(in transaction: inout GraphTransaction) throws {
        try body(&transaction)
    }
}

/// What the V1 fixture holds, as V1 wrote it. Fields differ from their
/// defaults where they can, so a stage that resets a field fails the test.
enum V1Fixture {
    static let outputPath = ProcessInfo.processInfo.environment["MINDMAP_WRITE_V1_FIXTURE"]

    static let mapID = MapID(UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
    static let rootID = NodeID(UUID(uuidString: "22222222-2222-4222-8222-222222222222")!)
    static let childID = NodeID(UUID(uuidString: "33333333-3333-4333-8333-333333333333")!)
    static let siblingID = NodeID(UUID(uuidString: "44444444-4444-4444-8444-444444444444")!)
    static let edgeID = EdgeID(UUID(uuidString: "55555555-5555-4555-8555-555555555555")!)
    static let created = Date(timeIntervalSinceReferenceDate: 1_000)
    static let edited = Date(timeIntervalSinceReferenceDate: 2_000)

    static let graph = GraphState(
        map: MindMap(
            id: mapID, title: "V1 fixture", rootNodeID: rootID,
            createdAt: created, updatedAt: edited, isFavorite: true, theme: .graphite
        ),
        nodes: [
            MindNode(id: rootID, mapID: mapID, parentID: nil, title: "V1 fixture", createdAt: created),
            MindNode(
                id: childID, mapID: mapID, parentID: rootID, title: "Child", note: "Migration keeps notes",
                sortOrder: 1, isCollapsed: true, metadata: NodeMetadata(origin: .ai), createdAt: created, updatedAt: edited
            ),
            MindNode(id: siblingID, mapID: mapID, parentID: rootID, title: "Sibling", sortOrder: 2, createdAt: created),
        ],
        edges: [
            MindEdge(
                id: edgeID, mapID: mapID, sourceNodeID: childID, targetNodeID: siblingID,
                edgeType: .reference, label: "cites", createdAt: created
            ),
        ]
    )

    /// Uses the `SchemaV1` types and raw values directly, never the current
    /// typealiases or record mapping, so it keeps writing V1 after V2 ships.
    static func write(to url: URL) throws {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration("V1Fixture", schema: schema, url: url, cloudKitDatabase: .none)
        let context = ModelContext(try ModelContainer(for: schema, configurations: configuration))

        let map = SchemaV1.MapRecord(mapID: mapID.rawValue)
        map.title = "V1 fixture"
        map.rootNodeID = rootID.rawValue
        map.createdAt = created
        map.updatedAt = edited
        map.isFavorite = true
        map.themeRaw = "graphite"
        map.layoutStyleRaw = "horizontalTree"
        context.insert(map)

        let root = SchemaV1.NodeRecord(nodeID: rootID.rawValue, mapID: mapID.rawValue)
        root.title = "V1 fixture"
        root.createdAt = created
        root.updatedAt = created
        context.insert(root)

        let child = SchemaV1.NodeRecord(nodeID: childID.rawValue, mapID: mapID.rawValue)
        child.parentID = rootID.rawValue
        child.title = "Child"
        child.note = "Migration keeps notes"
        child.sortOrder = 1
        child.isCollapsed = true
        child.originRaw = "ai"
        child.createdAt = created
        child.updatedAt = edited
        context.insert(child)

        let sibling = SchemaV1.NodeRecord(nodeID: siblingID.rawValue, mapID: mapID.rawValue)
        sibling.parentID = rootID.rawValue
        sibling.title = "Sibling"
        sibling.sortOrder = 2
        sibling.createdAt = created
        sibling.updatedAt = created
        context.insert(sibling)

        let edge = SchemaV1.EdgeRecord(edgeID: edgeID.rawValue, mapID: mapID.rawValue)
        edge.sourceNodeID = childID.rawValue
        edge.targetNodeID = siblingID.rawValue
        edge.edgeTypeRaw = "reference"
        edge.label = "cites"
        edge.createdAt = created
        edge.updatedAt = created
        context.insert(edge)

        try context.save()
    }
}

/// A private copy of a checked-in store. Opening a store can migrate it in
/// place and adds `-wal` and `-shm` files beside it, so the fixture itself is
/// never opened.
struct FixtureStore {
    let url: URL
    private let folder: URL

    init(copying name: String) throws {
        let fixture = try #require(Bundle.module.url(forResource: name, withExtension: "store", subdirectory: "Fixtures"))
        folder = FileManager.default.temporaryDirectory.appending(path: "fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appending(path: "\(name).store")
        try FileManager.default.copyItem(at: fixture, to: url)
    }

    func remove() {
        try? FileManager.default.removeItem(at: folder)
    }
}

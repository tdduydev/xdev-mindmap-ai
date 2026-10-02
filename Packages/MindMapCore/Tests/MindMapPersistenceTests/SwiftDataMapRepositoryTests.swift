import Foundation
import MindMapDomain
import MindMapGraph
@testable import MindMapPersistence
import SwiftData
import Testing

@Suite("SwiftData repository")
struct SwiftDataMapRepositoryTests {
    let container: ModelContainer
    let repository: SwiftDataMapRepository

    init() throws {
        container = try PersistenceController.makeContainer(at: .inMemory)
        repository = SwiftDataMapRepository(modelContainer: container)
    }

    @Test func createdGraphLoadsBackUnchanged() async throws {
        let graph = try Self.sampleGraph()

        try await repository.create(graph)
        let loaded = try await repository.loadGraph(for: graph.map.id)

        #expect(loaded == graph)
    }

    @Test func savedChangesReloadExactly() async throws {
        var engine = try GraphEngine(state: GraphState.newMap(title: "Plan"))
        try await repository.create(engine.state)
        let rootID = try #require(engine.state.map.rootNodeID)
        let a = NodeID()
        let b = NodeID()
        let commands: [any GraphCommand] = [
            AddNodeCommand(nodeID: a, .child(of: rootID), title: "A"),
            AddNodeCommand(nodeID: b, .child(of: rootID), title: "B"),
            AddNodeCommand(.child(of: a), title: "A1"),
            UpdateNodeCommand(nodeID: b, changes: [.title("Beta"), .note("Thiết kế backend architecture")]),
            ReparentNodeCommand(nodeID: b, newParentID: a, placement: .first),
            DeleteNodeCommand(nodeID: b),
        ]

        for command in commands {
            let changes = try engine.execute(command)
            try await repository.save(changes, map: engine.state.map)
        }
        if let changes = engine.undo() {
            try await repository.save(changes, map: engine.state.map)
        }

        let loaded = try await repository.loadGraph(for: engine.state.map.id)
        #expect(loaded == engine.state)
    }

    @Test func mapsComeNewestFirst() async throws {
        let older = GraphState.newMap(title: "Older", now: Date(timeIntervalSinceReferenceDate: 1_000))
        let newer = GraphState.newMap(title: "Newer", now: Date(timeIntervalSinceReferenceDate: 2_000))
        try await repository.create(older)
        try await repository.create(newer)

        let titles = try await repository.fetchMaps().map(\.title)

        #expect(titles == ["Newer", "Older"])
    }

    @Test func favoriteIsNotAnEdit() async throws {
        let graph = try Self.sampleGraph()
        try await repository.create(graph)

        try await repository.setFavorite(true, for: graph.map.id)

        let loaded = try #require(try await repository.loadGraph(for: graph.map.id))
        #expect(loaded.map.isFavorite)
        #expect(loaded.map.updatedAt == graph.map.updatedAt)
        #expect(loaded.nodes == graph.nodes)
    }

    /// The library can star a map while its editor is open with an older copy;
    /// the editor's next save must not take the star away.
    @Test func editorSaveKeepsAFavoriteSetElsewhere() async throws {
        var engine = try GraphEngine(state: GraphState.newMap(title: "Open in editor"))
        try await repository.create(engine.state)
        try await repository.setFavorite(true, for: engine.state.map.id)
        let rootID = try #require(engine.state.map.rootNodeID)

        let changes = try engine.execute(AddNodeCommand(.child(of: rootID), title: "New idea"))
        #expect(engine.state.map.isFavorite == false)
        try await repository.save(changes, map: engine.state.map)

        let loaded = try #require(try await repository.loadGraph(for: engine.state.map.id))
        #expect(loaded.map.isFavorite)
        #expect(loaded.nodes == engine.state.nodes)
    }

    @Test func deletingAMapDeletesAllItsRecords() async throws {
        let kept = try Self.sampleGraph()
        let doomed = try Self.sampleGraph()
        try await repository.create(kept)
        try await repository.create(doomed)

        try await repository.deleteMap(doomed.map.id)

        #expect(try await repository.loadGraph(for: doomed.map.id) == nil)
        #expect(try await repository.fetchMaps().map(\.id) == [kept.map.id])
        let doomedID = doomed.map.id.rawValue
        let context = ModelContext(container)
        #expect(try context.fetchCount(FetchDescriptor<NodeRecord>(predicate: #Predicate { $0.mapID == doomedID })) == 0)
        #expect(try context.fetchCount(FetchDescriptor<EdgeRecord>(predicate: #Predicate { $0.mapID == doomedID })) == 0)
        #expect(try context.fetchCount(FetchDescriptor<NodeRecord>()) == kept.nodes.count)
    }

    @Test func missingMapLoadsAsNil() async throws {
        #expect(try await repository.loadGraph(for: MapID()) == nil)
    }

    /// Sync can deliver one node twice. Loading keeps the newest copy and the
    /// next save folds the copies into one record.
    @Test func duplicateRecordsAreFolded() async throws {
        var graph = GraphState.newMap(title: "Dupes")
        try await repository.create(graph)
        let root = try #require(graph.root)
        let context = ModelContext(container)
        let stale = NodeRecord(nodeID: root.id.rawValue, mapID: root.mapID.rawValue)
        var older = root
        older.title = "Stale copy"
        older.updatedAt = root.updatedAt.addingTimeInterval(-60)
        stale.update(from: older)
        context.insert(stale)
        try context.save()

        let loaded = try #require(try await repository.loadGraph(for: graph.map.id))
        #expect(loaded.root?.title == "Dupes")

        var engine = try GraphEngine(state: loaded)
        let changes = try engine.execute(UpdateNodeCommand(nodeID: root.id, .title("Renamed")))
        try await repository.save(changes, map: engine.state.map)
        graph = try #require(try await repository.loadGraph(for: graph.map.id))

        let rootID = root.id.rawValue
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<NodeRecord>(predicate: #Predicate { $0.nodeID == rootID })) == 1)
        #expect(graph.root?.title == "Renamed")
    }

    /// A newer app version on another device may write values this build does not know.
    @Test func unknownStoredValuesDoNotBreakLoading() async throws {
        let graph = GraphState.newMap(title: "Future")
        try await repository.create(graph)
        let rootID = try #require(graph.map.rootNodeID)
        let context = ModelContext(container)
        let child = NodeRecord(nodeID: UUID(), mapID: graph.map.id.rawValue)
        child.parentID = rootID.rawValue
        child.title = "From a newer version"
        child.nodeTypeRaw = "kanbanCard"
        child.originRaw = "somethingElse"
        context.insert(child)
        let edge = EdgeRecord(edgeID: UUID(), mapID: graph.map.id.rawValue)
        edge.sourceNodeID = rootID.rawValue
        edge.targetNodeID = child.nodeID
        edge.edgeTypeRaw = "dependsOn"
        context.insert(edge)
        try context.save()

        let loaded = try #require(try await repository.loadGraph(for: graph.map.id))

        let loadedChild = try #require(loaded.node(NodeID(child.nodeID)))
        #expect(loadedChild.nodeType == .topic)
        #expect(loadedChild.metadata.origin == .user)
        #expect(loaded.edges.isEmpty)
    }

    static func sampleGraph() throws -> GraphState {
        var engine = try GraphEngine(state: GraphState.newMap(title: "AI Platform"))
        let rootID = try #require(engine.state.map.rootNodeID)
        let rag = NodeID()
        let models = NodeID()
        try engine.execute(BatchCommand([
            AddNodeCommand(nodeID: rag, .child(of: rootID), title: "RAG"),
            AddNodeCommand(.child(of: rag), title: "Embedding"),
            AddNodeCommand(.child(of: rag), title: "Vector Database", note: "Local first"),
            AddNodeCommand(nodeID: models, .child(of: rootID), title: "Models", metadata: NodeMetadata(origin: .ai)),
            UpdateNodeCommand(nodeID: models, .isCollapsed(true)),
            ConnectForTest(edge: MindEdge(mapID: engine.state.map.id, sourceNodeID: models, targetNodeID: rag, label: "feeds")),
        ]))
        return engine.state
    }
}

@Suite("Store on disk")
struct PersistenceControllerTests {
    @Test func graphSurvivesReopeningTheStore() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "MindMapAI-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "MindMapAI.store")
        let graph = try SwiftDataMapRepositoryTests.sampleGraph()

        try await PersistenceController.makeRepository(at: .file(url)).create(graph)
        let reopened = try PersistenceController.makeRepository(at: .file(url))

        #expect(try await reopened.loadGraph(for: graph.map.id) == graph)
    }

    @Test func migrationPlanEndsAtTheCurrentSchema() throws {
        let schemas = MindMapMigrationPlan.schemas
        #expect(schemas.map { ObjectIdentifier($0) } == [ObjectIdentifier(SchemaV1.self), ObjectIdentifier(SchemaV2.self)])
        #expect(ObjectIdentifier(CurrentSchema.self) == ObjectIdentifier(SchemaV2.self))
        #expect(SchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(SchemaV2.versionIdentifier == Schema.Version(2, 0, 0))
    }
}

/// Relationship editing arrives with MM-1; tests add edges through the transaction.
struct ConnectForTest: GraphCommand {
    let edge: MindEdge

    func execute(in transaction: inout GraphTransaction) throws {
        try transaction.insertEdge(edge)
    }
}

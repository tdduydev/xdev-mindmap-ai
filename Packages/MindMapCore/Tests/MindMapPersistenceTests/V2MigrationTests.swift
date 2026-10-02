import Foundation
import MindMapAICore
import MindMapDomain
import MindMapGraph
@testable import MindMapPersistence
import SwiftData
import Testing

/// Opens `Fixtures/V2.store`, written by SchemaV2 as builds 202610030024 and
/// 202610030030 shipped it, with today's plan: the V2 → V3 stage keeps every
/// V2 value and adds an empty chat to each map (MM-55).
@Suite("Migration from V2")
struct V2MigrationTests {
    @Test func v2StoreOpensAsV3WithEveryValue() async throws {
        let store = try FixtureStore(copying: "V2")
        defer { store.remove() }
        let container = try PersistenceController.makeContainer(at: .file(store.url))
        #expect(container.schema.version == SchemaV3.versionIdentifier)

        let context = ModelContext(container)
        let map = try #require(try context.fetch(FetchDescriptor<MapRecord>()).first)
        #expect(map.mapID == V2Fixture.mapID && map.title == "V2 fixture" && map.isFavorite)
        #expect(map.themeRaw == "graphite" && map.deletedAt == nil)
        let child = try #require(try context.fetch(NodeRecord.withIDs([V2Fixture.childID])).first)
        #expect(child.note == "Migration keeps notes" && child.colorToken == "teal" && child.symbol == "flag")
        #expect(child.taskStateRaw == "open" && child.priority == 1 && child.dueDate == "2026-12-31")
        #expect(child.linkURL == "https://example.com/plan" && child.calloutText == "Check the budget")
        let floating = try #require(try context.fetch(NodeRecord.withIDs([V2Fixture.floatingID])).first)
        #expect(floating.positionX == -120.5 && floating.positionY == 64)
        let edge = try #require(try context.fetch(FetchDescriptor<EdgeRecord>()).first)
        #expect(edge.label == "cites" && edge.lineStyleRaw == "dashed" && edge.arrowHeadsRaw == "end" && edge.colorToken == "rose")
        let tags = try context.fetch(FetchDescriptor<TagRecord>())
        #expect(Set(tags.map(\.name)) == ["Risk", "Shared"])
        #expect(tags.first { $0.name == "Shared" }?.mapID == nil)
        #expect(try context.fetchCount(FetchDescriptor<NodeTagRecord>()) == 1)
        let group = try #require(try context.fetch(FetchDescriptor<GroupRecord>()).first)
        #expect(group.title == "Both" && group.firstNodeID == V2Fixture.childID && group.lastNodeID == V2Fixture.siblingID)
        let image = try #require(try context.fetch(FetchDescriptor<ImageRecord>()).first)
        #expect(image.data == V2Fixture.imageBytes && image.altText == "Whiteboard")
        #expect(try context.fetchCount(FetchDescriptor<ChatTurnRecord>()) == 0)

        let repository = SwiftDataMapRepository(modelContainer: container)
        let graph = try #require(try await repository.loadGraph(for: MapID(V2Fixture.mapID)))
        #expect(graph.nodes.count == 4 && graph.tags.count == 2 && graph.nodeTags.count == 1)
        #expect(graph.node(NodeID(V2Fixture.childID))?.taskState == .open)
        #expect(try GraphRepair.repair(graph, now: .now).changes.isEmpty)
        #expect(try await repository.chatTurns(for: MapID(V2Fixture.mapID)).isEmpty)
    }

    /// A migrated V2 map takes a chat and keeps it, and its edits still save.
    @Test func migratedV2StoreKeepsChatAndEdits() async throws {
        let store = try FixtureStore(copying: "V2")
        defer { store.remove() }
        let mapID = MapID(V2Fixture.mapID)
        let repository = try PersistenceController.makeRepository(at: .file(store.url))
        let turn = ChatTurn(question: "What is due?", answer: "Child is due [T1].", citations: [
            ChatCitation(handle: "T1", mapID: mapID, nodeID: NodeID(V2Fixture.childID), title: "Child"),
        ])
        try await repository.appendChatTurn(turn, to: mapID, at: .now)
        var engine = try GraphEngine(state: try #require(try await repository.loadGraph(for: mapID)))
        let changes = try engine.execute(AddNodeCommand(.child(of: NodeID(V2Fixture.rootID)), title: "Added after migration"))
        try await repository.save(changes, map: engine.state.map)

        let reopened = try PersistenceController.makeRepository(at: .file(store.url))
        #expect(try await reopened.chatTurns(for: mapID) == [turn])
        #expect(try await reopened.loadGraph(for: mapID) == engine.state)
    }

    /// Writes `Fixtures/V2.store`. Runs only when asked: the checked-in
    /// fixture must stay what V2 wrote (docs/data-model.md).
    @Test(.enabled(if: V2Fixture.outputPath != nil))
    func writeV2Fixture() throws {
        try V2Fixture.write(to: URL(fileURLWithPath: try #require(V2Fixture.outputPath)))
    }
}

/// What the V2 fixture holds. Every V2 field differs from its default
/// somewhere, so a stage that resets one fails the test.
enum V2Fixture {
    static let outputPath = ProcessInfo.processInfo.environment["MINDMAP_WRITE_V2_FIXTURE"]

    static let mapID = UUID(uuidString: "a1111111-1111-4111-8111-111111111111")!
    static let rootID = UUID(uuidString: "a2222222-2222-4222-8222-222222222222")!
    static let childID = UUID(uuidString: "a3333333-3333-4333-8333-333333333333")!
    static let siblingID = UUID(uuidString: "a4444444-4444-4444-8444-444444444444")!
    static let floatingID = UUID(uuidString: "a5555555-5555-4555-8555-555555555555")!
    static let created = Date(timeIntervalSinceReferenceDate: 1_000)
    static let edited = Date(timeIntervalSinceReferenceDate: 2_000)
    static let imageBytes = Data((0..<255).map(UInt8.init))

    /// `SchemaV2` types and raw values only, never the current typealiases or
    /// record mapping, so it keeps writing V2 after V3 ships.
    static func write(to url: URL) throws {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let configuration = ModelConfiguration("V2Fixture", schema: schema, url: url, cloudKitDatabase: .none)
        let context = ModelContext(try ModelContainer(for: schema, configurations: configuration))

        let map = SchemaV2.MapRecord(mapID: mapID)
        map.title = "V2 fixture"
        map.rootNodeID = rootID
        map.createdAt = created
        map.updatedAt = edited
        map.isFavorite = true
        map.themeRaw = "graphite"
        context.insert(map)

        func node(_ id: UUID, parent: UUID?, title: String, order: Double) -> SchemaV2.NodeRecord {
            let record = SchemaV2.NodeRecord(nodeID: id, mapID: mapID)
            record.parentID = parent
            record.title = title
            record.sortOrder = order
            record.createdAt = created
            record.updatedAt = created
            context.insert(record)
            return record
        }
        _ = node(rootID, parent: nil, title: "V2 fixture", order: 0)
        let child = node(childID, parent: rootID, title: "Child", order: 1)
        child.note = "Migration keeps notes"
        child.isCollapsed = true
        child.originRaw = "ai"
        child.colorToken = "teal"
        child.symbol = "flag"
        child.taskStateRaw = "open"
        child.priority = 1
        child.startDate = "2026-12-01"
        child.dueDate = "2026-12-31"
        child.linkURL = "https://example.com/plan"
        child.calloutText = "Check the budget"
        _ = node(siblingID, parent: rootID, title: "Sibling", order: 2)
        let floating = node(floatingID, parent: nil, title: "Floating", order: 3)
        floating.positionX = -120.5
        floating.positionY = 64

        let edge = SchemaV2.EdgeRecord(edgeID: UUID(), mapID: mapID)
        edge.sourceNodeID = childID
        edge.targetNodeID = siblingID
        edge.edgeTypeRaw = "reference"
        edge.label = "cites"
        edge.lineStyleRaw = "dashed"
        edge.arrowHeadsRaw = "end"
        edge.colorToken = "rose"
        edge.createdAt = created
        edge.updatedAt = created
        context.insert(edge)

        let tag = SchemaV2.TagRecord(tagID: UUID(), mapID: mapID)
        tag.name = "Risk"
        tag.colorToken = "amber"
        tag.createdAt = created
        context.insert(tag)
        let shared = SchemaV2.TagRecord(tagID: UUID(), mapID: nil)
        shared.name = "Shared"
        shared.sortOrder = 1
        shared.createdAt = created
        context.insert(shared)
        let link = SchemaV2.NodeTagRecord(linkID: UUID(), mapID: mapID)
        link.nodeID = childID
        link.tagID = tag.tagID
        link.createdAt = created
        context.insert(link)

        let group = SchemaV2.GroupRecord(groupID: UUID(), mapID: mapID)
        group.parentNodeID = rootID
        group.firstNodeID = childID
        group.lastNodeID = siblingID
        group.title = "Both"
        group.colorToken = "violet"
        group.createdAt = created
        context.insert(group)

        let image = SchemaV2.ImageRecord(imageID: UUID(), mapID: mapID)
        image.nodeID = siblingID
        image.data = imageBytes
        image.uniformType = "public.png"
        image.pixelWidth = 16
        image.pixelHeight = 9
        image.byteCount = imageBytes.count
        image.displayWidth = 240
        image.altText = "Whiteboard"
        image.createdAt = created
        context.insert(image)

        try context.save()
    }
}

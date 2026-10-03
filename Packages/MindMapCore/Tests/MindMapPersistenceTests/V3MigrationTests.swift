import Foundation
import MindMapAICore
import MindMapDomain
import MindMapGraph
@testable import MindMapPersistence
import SwiftData
import Testing

/// Opens `Fixtures/V3.store`, written by SchemaV3 as 1.0.0 (builds
/// 202610031203 and 202610031207) shipped it, with today's plan, so the next
/// schema's stage is tested against real V3 data (MM-99).
@Suite("Store from V3")
struct V3MigrationTests {
    @Test func v3StoreOpensWithEveryValue() async throws {
        let store = try FixtureStore(copying: "V3")
        defer { store.remove() }
        let container = try PersistenceController.makeContainer(at: .file(store.url))
        let context = ModelContext(container)

        let maps = try context.fetch(FetchDescriptor<MapRecord>(sortBy: [SortDescriptor(\.title)]))
        #expect(maps.count == 2)
        let map = try #require(maps.first { $0.mapID == V3Fixture.mapID })
        #expect(map.title == "V3 fixture" && map.rootNodeID == V3Fixture.rootID && map.isFavorite)
        #expect(map.themeRaw == "graphite" && map.layoutStyleRaw == "horizontalTree" && map.deletedAt == nil)
        #expect(map.createdAt == V3Fixture.created && map.updatedAt == V3Fixture.edited)
        let deleted = try #require(maps.first { $0.mapID == V3Fixture.deletedMapID })
        #expect(deleted.title == "Deleted map" && deleted.deletedAt == V3Fixture.deletedAt)

        let child = try #require(try context.fetch(NodeRecord.withIDs([V3Fixture.childID])).first)
        #expect(child.parentID == V3Fixture.rootID && child.title == "Child" && child.sortOrder == 1)
        #expect(child.note == "Migration keeps notes" && child.isCollapsed && child.originRaw == "ai")
        #expect(child.colorToken == "teal" && child.symbol == "flag")
        #expect(child.taskStateRaw == "done" && child.priority == 2)
        #expect(child.startDate == "2026-11-01" && child.dueDate == "2026-11-30")
        #expect(child.linkURL == "https://example.com/plan" && child.calloutText == "Check the budget")
        #expect(child.createdAt == V3Fixture.created && child.updatedAt == V3Fixture.edited)
        let floating = try #require(try context.fetch(NodeRecord.withIDs([V3Fixture.floatingID])).first)
        #expect(floating.parentID == nil && floating.positionX == 88.25 && floating.positionY == -42)

        let edge = try #require(try context.fetch(FetchDescriptor<EdgeRecord>()).first)
        #expect(edge.edgeID == V3Fixture.edgeID && edge.sourceNodeID == V3Fixture.childID && edge.targetNodeID == V3Fixture.siblingID)
        #expect(edge.edgeTypeRaw == "reference" && edge.label == "cites")
        #expect(edge.lineStyleRaw == "dotted" && edge.arrowHeadsRaw == "both" && edge.colorToken == "rose")

        let tags = try context.fetch(FetchDescriptor<TagRecord>())
        let tag = try #require(tags.first { $0.tagID == V3Fixture.tagID })
        #expect(tag.mapID == V3Fixture.mapID && tag.name == "Risk" && tag.colorToken == "amber")
        let shared = try #require(tags.first { $0.tagID == V3Fixture.sharedTagID })
        #expect(shared.mapID == nil && shared.name == "Shared" && shared.sortOrder == 1)
        let link = try #require(try context.fetch(FetchDescriptor<NodeTagRecord>()).first)
        #expect(link.nodeID == V3Fixture.childID && link.tagID == V3Fixture.tagID && link.mapID == V3Fixture.mapID)

        let group = try #require(try context.fetch(FetchDescriptor<GroupRecord>()).first)
        #expect(group.parentNodeID == V3Fixture.rootID && group.title == "Both" && group.colorToken == "violet")
        #expect(group.firstNodeID == V3Fixture.childID && group.lastNodeID == V3Fixture.siblingID)
        let image = try #require(try context.fetch(FetchDescriptor<ImageRecord>()).first)
        #expect(image.nodeID == V3Fixture.siblingID && image.data == V3Fixture.imageBytes)
        #expect(image.uniformType == "public.png" && image.pixelWidth == 16 && image.pixelHeight == 9)
        #expect(image.byteCount == V3Fixture.imageBytes.count && image.displayWidth == 240 && image.altText == "Whiteboard")

        let records = try context.fetch(FetchDescriptor<ChatTurnRecord>(sortBy: [SortDescriptor(\.createdAt)]))
        #expect(records.map(\.turnID) == [V3Fixture.turn1ID, V3Fixture.turn2ID, V3Fixture.turn3ID, V3Fixture.deletedTurnID])
        #expect(records.map(\.createdAt) == [V3Fixture.asked(1), V3Fixture.asked(2), V3Fixture.asked(3), V3Fixture.asked(4)])
        #expect(records.map(\.citationsData) == [
            V3Fixture.arrayCitations, V3Fixture.branchCitations, nil, V3Fixture.arrayCitations,
        ])

        let repository = SwiftDataMapRepository(modelContainer: container)
        let graph = try #require(try await repository.loadGraph(for: MapID(V3Fixture.mapID)))
        #expect(graph.nodes.count == 4 && graph.edges.count == 1 && graph.tags.count == 2 && graph.nodeTags.count == 1)
        #expect(graph.groups.count == 1 && graph.images.count == 1)
        #expect(graph.node(NodeID(V3Fixture.childID))?.taskState == .done)
        #expect(try GraphRepair.repair(graph, now: .now).changes.isEmpty)
        #expect(try await repository.fetchDeletedMaps().map(\.id) == [MapID(V3Fixture.deletedMapID)])
        #expect(try await repository.chatTurns(for: MapID(V3Fixture.mapID)) == V3Fixture.expectedTurns)
        #expect(try await repository.chatTurns(for: MapID(V3Fixture.deletedMapID)).map(\.id) == [V3Fixture.deletedTurnID])
    }

    /// A V3 store keeps taking chat turns and edits after it is opened.
    @Test func v3StoreKeepsChatAndEdits() async throws {
        let store = try FixtureStore(copying: "V3")
        defer { store.remove() }
        let mapID = MapID(V3Fixture.mapID)
        let repository = try PersistenceController.makeRepository(at: .file(store.url))
        let turn = ChatTurn(question: "What is left?", answer: "Nothing.", citations: [])
        try await repository.appendChatTurn(turn, to: mapID, at: V3Fixture.asked(10))
        var engine = try GraphEngine(state: try #require(try await repository.loadGraph(for: mapID)))
        let changes = try engine.execute(AddNodeCommand(.child(of: NodeID(V3Fixture.rootID)), title: "Added after opening"))
        try await repository.save(changes, map: engine.state.map)

        let reopened = try PersistenceController.makeRepository(at: .file(store.url))
        #expect(try await reopened.chatTurns(for: mapID) == V3Fixture.expectedTurns + [turn])
        #expect(try await reopened.loadGraph(for: mapID) == engine.state)
    }

    /// Writes `Fixtures/V3.store`. Runs only when asked: the checked-in
    /// fixture must stay what V3 wrote (docs/data-model.md).
    @Test(.enabled(if: V3Fixture.outputPath != nil))
    func writeV3Fixture() throws {
        try V3Fixture.write(to: URL(fileURLWithPath: try #require(V3Fixture.outputPath)))
    }
}

/// What the V3 fixture holds. Every V3 field differs from its default
/// somewhere, and from the V2 fixture's values, so a stage that resets a
/// field or copies the wrong one fails the test.
enum V3Fixture {
    static let outputPath = ProcessInfo.processInfo.environment["MINDMAP_WRITE_V3_FIXTURE"]

    static let mapID = UUID(uuidString: "b1111111-1111-4111-8111-111111111111")!
    static let rootID = UUID(uuidString: "b2222222-2222-4222-8222-222222222222")!
    static let childID = UUID(uuidString: "b3333333-3333-4333-8333-333333333333")!
    static let siblingID = UUID(uuidString: "b4444444-4444-4444-8444-444444444444")!
    static let floatingID = UUID(uuidString: "b5555555-5555-4555-8555-555555555555")!
    static let edgeID = UUID(uuidString: "b6666666-6666-4666-8666-666666666666")!
    static let tagID = UUID(uuidString: "b7777777-7777-4777-8777-777777777777")!
    static let sharedTagID = UUID(uuidString: "b8888888-8888-4888-8888-888888888888")!
    static let deletedMapID = UUID(uuidString: "b9999999-9999-4999-8999-999999999999")!
    static let deletedRootID = UUID(uuidString: "baaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
    static let turn1ID = UUID(uuidString: "c1111111-1111-4111-8111-111111111111")!
    static let turn2ID = UUID(uuidString: "c2222222-2222-4222-8222-222222222222")!
    static let turn3ID = UUID(uuidString: "c3333333-3333-4333-8333-333333333333")!
    static let deletedTurnID = UUID(uuidString: "c4444444-4444-4444-8444-444444444444")!
    static let created = Date(timeIntervalSinceReferenceDate: 3_000)
    static let edited = Date(timeIntervalSinceReferenceDate: 4_000)
    static let deletedAt = Date(timeIntervalSinceReferenceDate: 5_000)
    static let imageBytes = Data((0..<255).reversed().map(UInt8.init))

    static func asked(_ turn: Int) -> Date {
        Date(timeIntervalSinceReferenceDate: 6_000 + Double(turn))
    }

    // The citation JSON as 1.0.0 wrote it, spelled out instead of encoded from
    // today's types, so a change to those types cannot change the fixture.
    /// A whole-map turn: MM-55's plain array.
    static let arrayCitations = Data("""
    [{"handle":"T1","mapID":"B1111111-1111-4111-8111-111111111111",\
    "nodeID":"B3333333-3333-4333-8333-333333333333","title":"Child"}]
    """.utf8)
    /// A turn limited to a branch (MM-78): an object with the branch.
    static let branchCitations = Data("""
    {"citations":[{"handle":"T2","mapID":"B1111111-1111-4111-8111-111111111111",\
    "nodeID":"B4444444-4444-4444-8444-444444444444","title":"Sibling"}],\
    "branch":{"nodeID":"B2222222-2222-4222-8222-222222222222","title":"V3 fixture"}}
    """.utf8)

    static var expectedTurns: [ChatTurn] {
        let map = MapID(mapID)
        return [
            ChatTurn(id: turn1ID, question: "What is done?", answer: "Child is done [T1].", citations: [
                ChatCitation(handle: "T1", mapID: map, nodeID: NodeID(childID), title: "Child"),
            ]),
            ChatTurn(id: turn2ID, question: "What does this branch hold?", answer: "Sibling has a whiteboard [T2].", citations: [
                ChatCitation(handle: "T2", mapID: map, nodeID: NodeID(siblingID), title: "Sibling"),
            ], branch: ChatBranch(nodeID: NodeID(rootID), title: "V3 fixture")),
            ChatTurn(id: turn3ID, question: "Xin chào", answer: "Chào bạn.", citations: []),
        ]
    }

    /// `SchemaV3` types and raw values only, never the current typealiases or
    /// record mapping, so it keeps writing V3 after V4 ships.
    static func write(to url: URL) throws {
        let schema = Schema(versionedSchema: SchemaV3.self)
        let configuration = ModelConfiguration("V3Fixture", schema: schema, url: url, cloudKitDatabase: .none)
        let context = ModelContext(try ModelContainer(for: schema, configurations: configuration))

        let map = SchemaV3.MapRecord(mapID: mapID)
        map.title = "V3 fixture"
        map.rootNodeID = rootID
        map.createdAt = created
        map.updatedAt = edited
        map.isFavorite = true
        map.themeRaw = "graphite"
        context.insert(map)

        func node(_ id: UUID, in map: UUID = mapID, parent: UUID?, title: String, order: Double) -> SchemaV3.NodeRecord {
            let record = SchemaV3.NodeRecord(nodeID: id, mapID: map)
            record.parentID = parent
            record.title = title
            record.sortOrder = order
            record.createdAt = created
            record.updatedAt = created
            context.insert(record)
            return record
        }
        _ = node(rootID, parent: nil, title: "V3 fixture", order: 0)
        let child = node(childID, parent: rootID, title: "Child", order: 1)
        child.note = "Migration keeps notes"
        child.isCollapsed = true
        child.originRaw = "ai"
        child.updatedAt = edited
        child.colorToken = "teal"
        child.symbol = "flag"
        child.taskStateRaw = "done"
        child.priority = 2
        child.startDate = "2026-11-01"
        child.dueDate = "2026-11-30"
        child.linkURL = "https://example.com/plan"
        child.calloutText = "Check the budget"
        _ = node(siblingID, parent: rootID, title: "Sibling", order: 2)
        let floating = node(floatingID, parent: nil, title: "Floating", order: 3)
        floating.positionX = 88.25
        floating.positionY = -42

        let edge = SchemaV3.EdgeRecord(edgeID: edgeID, mapID: mapID)
        edge.sourceNodeID = childID
        edge.targetNodeID = siblingID
        edge.edgeTypeRaw = "reference"
        edge.label = "cites"
        edge.lineStyleRaw = "dotted"
        edge.arrowHeadsRaw = "both"
        edge.colorToken = "rose"
        edge.createdAt = created
        edge.updatedAt = created
        context.insert(edge)

        let tag = SchemaV3.TagRecord(tagID: tagID, mapID: mapID)
        tag.name = "Risk"
        tag.colorToken = "amber"
        tag.createdAt = created
        context.insert(tag)
        let shared = SchemaV3.TagRecord(tagID: sharedTagID, mapID: nil)
        shared.name = "Shared"
        shared.sortOrder = 1
        shared.createdAt = created
        context.insert(shared)
        let link = SchemaV3.NodeTagRecord(linkID: UUID(), mapID: mapID)
        link.nodeID = childID
        link.tagID = tagID
        link.createdAt = created
        context.insert(link)

        let group = SchemaV3.GroupRecord(groupID: UUID(), mapID: mapID)
        group.parentNodeID = rootID
        group.firstNodeID = childID
        group.lastNodeID = siblingID
        group.title = "Both"
        group.colorToken = "violet"
        group.createdAt = created
        context.insert(group)

        let image = SchemaV3.ImageRecord(imageID: UUID(), mapID: mapID)
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

        func turn(_ id: UUID, in map: UUID = mapID, question: String, answer: String, citations: Data?, at index: Int) {
            let record = SchemaV3.ChatTurnRecord(turnID: id, mapID: map)
            record.question = question
            record.answer = answer
            record.citationsData = citations
            record.createdAt = asked(index)
            context.insert(record)
        }
        // Inserted out of order: the conversation is ordered by createdAt.
        turn(turn3ID, question: "Xin chào", answer: "Chào bạn.", citations: nil, at: 3)
        turn(turn1ID, question: "What is done?", answer: "Child is done [T1].", citations: arrayCitations, at: 1)
        turn(turn2ID, question: "What does this branch hold?", answer: "Sibling has a whiteboard [T2].",
             citations: branchCitations, at: 2)

        // A map in Recently Deleted keeps its chat, so Restore brings it back.
        let deletedMap = SchemaV3.MapRecord(mapID: deletedMapID)
        deletedMap.title = "Deleted map"
        deletedMap.rootNodeID = deletedRootID
        deletedMap.createdAt = created
        deletedMap.updatedAt = created
        deletedMap.deletedAt = deletedAt
        context.insert(deletedMap)
        _ = node(deletedRootID, in: deletedMapID, parent: nil, title: "Deleted map", order: 0)
        turn(deletedTurnID, in: deletedMapID, question: "Gone?", answer: "Child [T1].", citations: arrayCitations, at: 4)

        try context.save()
    }
}

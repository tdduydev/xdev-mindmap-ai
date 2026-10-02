import Foundation
import MindMapDomain
import MindMapGraph
@testable import MindMapPersistence
import SwiftData
import Testing

@Suite("Stored organization (SchemaV2)")
struct OrganizationPersistenceTests {
    let container: ModelContainer
    let repository: SwiftDataMapRepository

    init() throws {
        container = try PersistenceController.makeContainer(at: .inMemory)
        repository = SwiftDataMapRepository(modelContainer: container)
    }

    /// A map using every V2 field: colour, symbol, task, styled link, tags and a boundary.
    static func organizedEngine() throws -> GraphEngine {
        var engine = try GraphEngine(state: GraphState.newMap(title: "Plan"))
        let rootID = try #require(engine.state.map.rootNodeID)
        let a = NodeID()
        let b = NodeID()
        let edgeID = EdgeID()
        try engine.execute(BatchCommand([
            AddNodeCommand(nodeID: a, .child(of: rootID), title: "A"),
            AddNodeCommand(nodeID: b, .child(of: rootID), title: "B"),
            SetNodeStyleCommand(nodeIDs: [a], color: .set(.violet), symbol: .set("star.fill")),
            SetTaskCommand(
                nodeIDs: [b], state: .set(.done), priority: .set(.medium),
                start: .set(CalendarDay(isoString: "2026-10-01")), due: .set(CalendarDay(isoString: "2026-10-09"))
            ),
            ConnectNodesCommand(edgeID: edgeID, from: a, to: b, label: "then"),
            StyleEdgeForTest(edgeID: edgeID, lineStyle: .dotted, arrowHeads: .both, color: .amber),
            TagNodesCommand(nodeIDs: [a, b], add: [.named("Việc")], origin: .ai),
            AddGroupCommand(from: a, to: b, title: "Phase 1", color: .graphite),
        ]))
        return engine
    }

    @Test func createdOrganizedGraphLoadsBackUnchanged() async throws {
        let engine = try Self.organizedEngine()

        try await repository.create(engine.state)

        #expect(try await repository.loadGraph(for: engine.state.map.id) == engine.state)
    }

    @Test func organizationCommandsSaveAndReloadExactly() async throws {
        var engine = try GraphEngine(state: GraphState.newMap(title: "Plan"))
        try await repository.create(engine.state)
        let rootID = try #require(engine.state.map.rootNodeID)
        let a = NodeID()
        let b = NodeID()
        let tagID = TagID()
        let groupID = GroupID()
        let commands: [any GraphCommand] = [
            AddNodeCommand(nodeID: a, .child(of: rootID), title: "A"),
            AddNodeCommand(nodeID: b, .child(of: rootID), title: "B"),
            TagNodesCommand(nodeIDs: [a, b], add: [.named("Work", newTagID: tagID)]),
            UpdateTagCommand(tagID: tagID, name: .set("Công việc"), color: .set(.blue)),
            SetTaskCommand(nodeIDs: [a], state: .set(.open), priority: .set(.high)),
            SetNodeStyleCommand(nodeIDs: [b], color: .set(.rose)),
            AddGroupCommand(groupID: groupID, from: a, to: b),
            UpdateGroupCommand(groupID: groupID, title: .set("Both")),
            DeleteNodeCommand(nodeID: a),
            TagNodesCommand(nodeIDs: [b], remove: [tagID]),
        ]
        for command in commands {
            let changes = try engine.execute(command)
            try await repository.save(changes, map: engine.state.map)
        }
        if let changes = engine.undo() {
            try await repository.save(changes, map: engine.state.map)
        }

        let loaded = try #require(try await repository.loadGraph(for: engine.state.map.id))
        #expect(loaded == engine.state)
        #expect(loaded.tags(of: b).map(\.name) == ["Công việc"])
        #expect(loaded.group(groupID).flatMap(loaded.members) == [b])
    }

    @Test func deletingTagsAndBoundariesDeletesTheirRecords() async throws {
        var engine = try Self.organizedEngine()
        try await repository.create(engine.state)
        let tagID = try #require(engine.state.tags.keys.first)
        let groupID = try #require(engine.state.groups.keys.first)

        for command: any GraphCommand in [DeleteTagCommand(tagID: tagID), RemoveGroupCommand(groupID: groupID)] {
            try await repository.save(try engine.execute(command), map: engine.state.map)
        }

        let context = ModelContext(container)
        #expect(try context.fetchCount(FetchDescriptor<TagRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<NodeTagRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<GroupRecord>()) == 0)
    }

    @Test func sharedTagsLoadWithEveryMapAndStayWhenOneIsDeleted() async throws {
        let first = GraphState.newMap(title: "First")
        let second = GraphState.newMap(title: "Second")
        try await repository.create(first)
        try await repository.create(second)
        let context = ModelContext(container)
        let shared = TagRecord(tagID: UUID(), mapID: nil)
        shared.name = "Việc"
        context.insert(shared)
        try context.save()

        #expect(try await repository.loadGraph(for: first.map.id)?.tags.count == 1)
        #expect(try await repository.loadGraph(for: second.map.id)?.tags.count == 1)

        try await repository.deleteMap(first.map.id)
        #expect(try context.fetchCount(FetchDescriptor<TagRecord>()) == 1)
    }

    @Test func deletingAMapDeletesItsOrganizationRecords() async throws {
        let engine = try Self.organizedEngine()
        try await repository.create(engine.state)

        try await repository.deleteMap(engine.state.map.id)

        let context = ModelContext(container)
        #expect(try context.fetchCount(FetchDescriptor<TagRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<NodeTagRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<GroupRecord>()) == 0)
    }

    /// Recently Deleted is library data: an editor's save must not clear it.
    @Test func editorSaveKeepsDeletedAt() async throws {
        var engine = try GraphEngine(state: GraphState.newMap(title: "Plan"))
        try await repository.create(engine.state)
        let deletedAt = Date(timeIntervalSinceReferenceDate: 5_000)
        let context = ModelContext(container)
        let mapID = engine.state.map.id.rawValue
        let record = try #require(try context.fetch(FetchDescriptor<MapRecord>(predicate: #Predicate { $0.mapID == mapID })).first)
        record.deletedAt = deletedAt
        try context.save()

        let changes = try engine.execute(RenameMapCommand(title: "Renamed"))
        try await repository.save(changes, map: engine.state.map)

        // fetchMaps lists live maps only (MM-19); the map must still be in Recently Deleted.
        #expect(try await repository.fetchMaps().isEmpty)
        #expect(try await repository.fetchDeletedMaps().first?.deletedAt == deletedAt)
    }

    /// Values from a newer version stay in storage after this build edits the topic.
    @Test func unknownStoredValuesSurviveAnEdit() async throws {
        var engine = try Self.organizedEngine()
        try await repository.create(engine.state)
        let context = ModelContext(container)
        let mapID = engine.state.map.id.rawValue
        let nodes = try context.fetch(FetchDescriptor<NodeRecord>(predicate: #Predicate { $0.mapID == mapID && $0.parentID != nil }))
        let node = try #require(nodes.first)
        node.colorToken = "magenta"
        node.taskStateRaw = "blocked"
        node.dueDate = "next tuesday"
        let group = try #require(try context.fetch(FetchDescriptor<GroupRecord>()).first)
        group.kindRaw = "zone"
        try context.save()

        var loaded = try #require(try await repository.loadGraph(for: engine.state.map.id))
        let nodeID = NodeID(node.nodeID)
        #expect(loaded.node(nodeID)?.color?.isKnown == false)
        #expect(loaded.node(nodeID)?.taskState?.isDone == false)
        #expect(loaded.node(nodeID)?.dueDate == nil)
        #expect(GraphValidator.validate(loaded).isEmpty)

        engine = try GraphEngine(state: loaded)
        try await repository.save(try engine.execute(UpdateNodeCommand(nodeID: nodeID, .title("Edited"))), map: engine.state.map)

        let fresh = ModelContext(container)
        let id = node.nodeID
        let stored = try #require(try fresh.fetch(FetchDescriptor<NodeRecord>(predicate: #Predicate { $0.nodeID == id })).first)
        #expect(stored.title == "Edited")
        #expect(stored.colorToken == "magenta")
        #expect(stored.taskStateRaw == "blocked")
        #expect(stored.dueDate == "next tuesday")
        loaded = try #require(try await repository.loadGraph(for: engine.state.map.id))
        #expect(loaded.groups.values.first?.kind.rawValue == "zone")
    }
}

/// Link styling commands arrive with MM-33; tests style links through the transaction.
struct StyleEdgeForTest: GraphCommand {
    let edgeID: EdgeID
    let lineStyle: EdgeLineStyle
    let arrowHeads: EdgeArrowHeads
    let color: TopicColor

    func execute(in transaction: inout GraphTransaction) throws {
        try transaction.updateEdge(edgeID) { edge in
            edge.lineStyle = lineStyle
            edge.arrowHeads = arrowHeads
            edge.color = color
        }
    }
}

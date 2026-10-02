import Foundation
import MindMapDomain
import MindMapGraph
@testable import MindMapPersistence
import SwiftData
import Testing

@Suite("Shared tag library actions")
struct SharedTagActionsTests {
    let container: ModelContainer
    let repository: SwiftDataMapRepository

    init() throws {
        container = try PersistenceController.makeContainer(at: .inMemory)
        repository = SwiftDataMapRepository(modelContainer: container)
    }

    /// Stores a shared tag the way the library holds it: no map.
    @MainActor
    private func storeSharedTag(_ name: String, createdAt: Date = Date(timeIntervalSinceReferenceDate: 1)) throws -> MindTag {
        let tag = MindTag(mapID: nil, name: name, createdAt: createdAt)
        let record = TagRecord.make(for: tag)
        record.update(from: tag)
        container.mainContext.insert(record)
        try container.mainContext.save()
        return tag
    }

    /// A stored map whose topic "A" carries `tags`, by ID or by name.
    private func storeMap(tagging tags: [TagReference]) async throws -> (graph: GraphState, nodeID: NodeID) {
        let shared = try await loadShared()
        var engine = try GraphEngine(state: GraphState(
            map: MindMap(title: "Map"), nodes: [], edges: [], tags: shared
        ))
        let rootID = NodeID()
        let a = NodeID()
        try engine.execute(BatchCommand([
            AddNodeCommand(nodeID: rootID, .root, title: "Map"),
            AddNodeCommand(nodeID: a, .child(of: rootID), title: "A"),
            TagNodesCommand(nodeIDs: [a], add: tags),
        ]))
        try await repository.create(engine.state)
        return (engine.state, a)
    }

    @MainActor
    private func loadShared() throws -> [MindTag] {
        try container.mainContext.fetch(FetchDescriptor<TagRecord>()).filter { $0.mapID == nil }.map(\.domainValue)
    }

    @Test func renameAndRecolourReachEveryMapAndArePublished() async throws {
        let tag = try await storeSharedTag("Việc")
        let first = try await storeMap(tagging: [.existing(tag.id)])
        let second = try await storeMap(tagging: [.existing(tag.id)])
        let changes = await repository.changes()

        let change = try await repository.renameSharedTag(tag.id, to: "  Công  việc ")
        try await repository.setSharedTagColor(tag.id, to: .rose)

        #expect(change.savedTags.map(\.name) == ["Công việc"])
        for map in [first, second] {
            let loaded = try #require(try await repository.loadGraph(for: map.graph.map.id))
            #expect(loaded.tags(of: map.nodeID).map(\.name) == ["Công việc"])
            #expect(loaded.tags(of: map.nodeID).map(\.color) == [.rose])
        }
        var iterator = changes.makeAsyncIterator()
        #expect(await iterator.next() == .tagsChanged(change))
        #expect(try await repository.sharedTagMapCounts() == [tag.id: 2])
    }

    @Test func renameRefusesAnotherSharedTagsNameAndMapTags() async throws {
        let tag = try await storeSharedTag("Việc")
        let other = try await storeSharedTag("Gấp")
        let map = try await storeMap(tagging: [.named("Riêng")])
        let mapTagID = try #require(map.graph.mapTags.first?.id)

        await #expect(throws: LibraryTagError.nameTaken(other.id)) { try await repository.renameSharedTag(tag.id, to: "GẤP") }
        await #expect(throws: LibraryTagError.invalidName) { try await repository.renameSharedTag(tag.id, to: "#") }
        await #expect(throws: LibraryTagError.wrongScope(mapTagID)) { try await repository.renameSharedTag(mapTagID, to: "X") }
    }

    @Test func deleteRemovesTheTagAndItsLinksInEveryMap() async throws {
        let tag = try await storeSharedTag("Việc")
        let first = try await storeMap(tagging: [.existing(tag.id)])
        let second = try await storeMap(tagging: [.existing(tag.id)])

        let change = try await repository.deleteSharedTag(tag.id)

        #expect(change.deletedTagIDs == [tag.id])
        #expect(change.deletedNodeTagIDs.count == 2)
        for map in [first, second] {
            let loaded = try #require(try await repository.loadGraph(for: map.graph.map.id))
            #expect(loaded.nodeTags.isEmpty)
            #expect(loaded.tags.isEmpty)
        }
    }

    @Test func mergeMovesLinksAndKeepsOneLinkPerTopic() async throws {
        let survivor = try await storeSharedTag("Việc", createdAt: Date(timeIntervalSinceReferenceDate: 1))
        let merged = try await storeSharedTag("Task", createdAt: Date(timeIntervalSinceReferenceDate: 2))
        let both = try await storeMap(tagging: [.existing(survivor.id), .existing(merged.id)])
        let onlyMerged = try await storeMap(tagging: [.existing(merged.id)])

        try await repository.mergeSharedTags(into: survivor.id, merging: [merged.id])

        for map in [both, onlyMerged] {
            let loaded = try #require(try await repository.loadGraph(for: map.graph.map.id))
            #expect(loaded.tags(of: map.nodeID).map(\.id) == [survivor.id])
            #expect(loaded.nodeTags.count == 1)
        }
        #expect(try await loadShared().map(\.id) == [survivor.id])
    }

    @Test func makeSharedAndBackToAMapTag() async throws {
        let map = try await storeMap(tagging: [.named("Việc")])
        let id = try #require(map.graph.mapTags.first?.id)

        try await repository.makeTagShared(id)
        let shared = try #require(try await repository.loadGraph(for: map.graph.map.id))
        #expect(shared.tag(id)?.isShared == true)
        let other = try await storeMap(tagging: [.existing(id)])
        await #expect(throws: LibraryTagError.usedInOtherMaps(count: 1)) {
            try await repository.makeMapTag(id, in: map.graph.map.id)
        }

        try await repository.deleteMap(other.graph.map.id)
        try await repository.makeMapTag(id, in: map.graph.map.id)
        let back = try #require(try await repository.loadGraph(for: map.graph.map.id))
        #expect(back.tag(id)?.mapID == map.graph.map.id)
        #expect(back.tags(of: map.nodeID).map(\.id) == [id])
    }

    @Test func makeSharedRefusesANameTheLibraryHas() async throws {
        let existing = try await storeSharedTag("VIỆC")
        let map = try await storeMap(tagging: [.named("Riêng")])
        let id = try #require(map.graph.mapTags.first?.id)
        try await repository.renameSharedTag(existing.id, to: "Riêng")

        await #expect(throws: LibraryTagError.nameTaken(existing.id)) { try await repository.makeTagShared(id) }
    }

    @Test func repairMergesSharedTagsWithTheSameKeyIntoTheOldest() async throws {
        let oldest = try await storeSharedTag("Việc", createdAt: Date(timeIntervalSinceReferenceDate: 1))
        let newer = try await storeSharedTag("VIỆC", createdAt: Date(timeIntervalSinceReferenceDate: 5))
        let map = try await storeMap(tagging: [.existing(newer.id)])

        let change = try await repository.repairSharedTags()
        let again = try await repository.repairSharedTags()

        #expect(change.deletedTagIDs == [newer.id])
        #expect(again.isEmpty)
        let loaded = try #require(try await repository.loadGraph(for: map.graph.map.id))
        #expect(loaded.tags(of: map.nodeID).map(\.id) == [oldest.id])
    }

    @Test func librarySearchTextsIncludeTagNames() async throws {
        let tag = try await storeSharedTag("Khẩn")
        let map = try await storeMap(tagging: [.existing(tag.id), .named("Riêng")])

        let texts = try await repository.fetchTopicTexts()

        #expect(Set(try #require(texts[map.graph.map.id])) == ["Map", "A", "Khẩn", "Riêng"])
    }
}

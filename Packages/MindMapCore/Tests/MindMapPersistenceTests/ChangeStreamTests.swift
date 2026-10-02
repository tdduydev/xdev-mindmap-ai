import Foundation
import MindMapDomain
import MindMapGraph
@testable import MindMapPersistence
import SwiftData
import Testing

@Suite("Repository changes")
struct ChangeStreamTests {
    @Test func committedWritesPublishChanges() async throws {
        let repository = try PersistenceController.makeRepository(at: .inMemory)
        let stream = await repository.changes()
        var iterator = stream.makeAsyncIterator()
        let graph = GraphState.newMap(title: "Stream")

        try await repository.create(graph)
        #expect(await iterator.next() != nil)

        var engine = try GraphEngine(state: graph)
        let root = try #require(graph.map.rootNodeID)
        let changes = try engine.execute(AddNodeCommand(.child(of: root), title: "Child"))
        try await repository.save(changes, map: engine.state.map)
        #expect(await iterator.next() != nil)

        try await repository.setFavorite(true, for: graph.map.id)
        #expect(await iterator.next() != nil)

        try await repository.deleteMap(graph.map.id)
        #expect(await iterator.next() != nil)
    }

    @Test func anotherContextInvalidatesTheLibrary() async throws {
        let container = try PersistenceController.makeContainer(at: .inMemory)
        let repository = SwiftDataMapRepository(modelContainer: container)
        let stream = await repository.changes()
        var iterator = stream.makeAsyncIterator()
        let context = ModelContext(container)
        let record = MapRecord(mapID: UUID())
        record.title = "Other window"
        context.insert(record)
        try context.save()

        #expect(await iterator.next() == .refresh)
        #expect(try await repository.fetchMaps().contains { $0.title == "Other window" })
    }
}

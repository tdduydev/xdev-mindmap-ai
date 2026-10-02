import Foundation
import MindMapDomain
import MindMapGraph
@testable import MindMapPersistence
import Testing

@Suite("Topic text for search")
struct TopicTextTests {
    @Test func returnsTitlesAndNotesByMap() async throws {
        let repository = try PersistenceController.makeRepository(at: .inMemory)
        let graph = try SwiftDataMapRepositoryTests.sampleGraph()
        let other = GraphState.newMap(title: "Other")
        try await repository.create(graph)
        try await repository.create(other)

        let texts = try await repository.fetchTopicTexts()

        let sample = try #require(texts[graph.map.id])
        #expect(Set(sample) == ["AI Platform", "RAG", "Embedding", "Vector Database", "Local first", "Models"])
        #expect(texts[other.map.id] == ["Other"])
    }

    @Test func followsDeletion() async throws {
        let repository = try PersistenceController.makeRepository(at: .inMemory)
        let graph = try SwiftDataMapRepositoryTests.sampleGraph()
        try await repository.create(graph)

        try await repository.deleteMap(graph.map.id)

        #expect(try await repository.fetchTopicTexts().isEmpty)
    }
}

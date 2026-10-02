import Foundation
import MindMapDomain
import MindMapGraph
import MindMapPersistence
@testable import MindMapQuery
import Testing

@Suite("Map queries with floating topics")
struct FloatingQueryTests {
    let repository: SwiftDataMapRepository
    let queries: MapQueries
    let built: MapQueriesTests.Built
    let floatingID = NodeID()
    let childID = NodeID()

    init() async throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
        queries = MapQueries(repository: repository, graphs: MapQueriesTests.OpenGraphs(repository: repository))
        var built = MapQueriesTests.build("Plan", [.topic("Design"), .topic("Budget")])
        let mapID = built.state.map.id
        let floating = MindNode(
            id: floatingID, mapID: mapID, parentID: nil, title: "Parking lot",
            note: "Ideas for later", position: TopicPosition(x: 200, y: 400)
        )
        let child = MindNode(id: childID, mapID: mapID, parentID: floatingID, title: "Zeppelin")
        built.state = GraphState(map: built.state.map, nodes: Array(built.state.nodes.values) + [floating, child], edges: [])
        self.built = built
        try await repository.create(built.state)
    }

    /// The whole map lists the main tree, then the floating branch from depth 0.
    @Test func outlineListsFloatingBranchesAfterTheTree() async throws {
        let outline = try await queries.outline(of: built.mapID, limit: .characters(10_000))

        #expect(outline.topics.map(\.title) == ["Plan", "Design", "Budget", "Parking lot", "Zeppelin"])
        #expect(outline.topics.map(\.depth) == [0, 1, 1, 0, 1])
        #expect(outline.topics.map(\.isFloating) == [false, false, false, true, false])

        let shallow = try await queries.outline(of: built.mapID, depth: 0, limit: .characters(10_000))
        #expect(shallow.topics.map(\.title) == ["Plan", "Parking lot"])
        #expect(shallow.deeperTopicCount == 3)

        let branch = try await queries.outline(of: built.mapID, branch: floatingID, limit: .characters(10_000))
        #expect(branch.topics.map(\.title) == ["Parking lot", "Zeppelin"])
    }

    /// Search across the library finds a map by a topic in a floating branch,
    /// with the path from the floating topic.
    @Test func searchFindsFloatingTopicsInClosedMaps() async throws {
        let hits = try await queries.search("zeppelin", limit: 10)
        #expect(hits.map(\.ref) == [TopicRef(mapID: built.mapID, nodeID: childID)])
        #expect(hits.first?.path == ["Parking lot"])

        let noteHits = try await queries.search("ideas later", limit: 10)
        #expect(noteHits.map(\.ref.nodeID) == [floatingID])
        #expect(noteHits.first?.path == [])
    }

    @Test func topicDetailOfAFloatingTopicHasNoPath() async throws {
        let detail = try #require(try await queries.topic(TopicRef(mapID: built.mapID, nodeID: floatingID)))
        #expect(detail.path.isEmpty)
        #expect(detail.children.map(\.title) == ["Zeppelin"])
    }
}

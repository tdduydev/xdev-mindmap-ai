import Foundation
import MindMapDomain
import MindMapGraph
import MindMapInterchange
import MindMapPersistence
@testable import MindMapSharing
import Testing

@Suite("Quick capture")
struct QuickCaptureTests {
    let repository: SwiftDataMapRepository
    let capture: QuickCapture

    init() throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
        capture = QuickCapture(repository: repository)
    }

    @Test func sharedTextAndLinkBecomeTopicsInOrder() {
        let draft = SharedContent.outline(of: [
            .text("- Ý tưởng\n  - Chi tiết"),
            .link(URL(string: "https://xdev.asia/a")!, title: "xDev"),
            .link(URL(string: "https://example.com")!, title: "  "),
        ])

        #expect(draft.items == [
            OutlineDraft.Item(depth: 0, title: "Ý tưởng"),
            OutlineDraft.Item(depth: 1, title: "Chi tiết"),
            OutlineDraft.Item(depth: 0, title: "xDev", note: "https://xdev.asia/a"),
            OutlineDraft.Item(depth: 0, title: "https://example.com"),
        ])
    }

    @Test func newMapFromSharedContent() async throws {
        let draft = SharedContent.outline(of: [.text("Alpha\nBeta")])

        let map = try await capture.createMap(from: draft, title: "Shared")

        let graph = try #require(try await repository.loadGraph(for: map.id))
        #expect(graph.map.title == "Shared")
        let rootID = try #require(graph.map.rootNodeID)
        #expect(graph.children(of: rootID).map(\.title) == ["Alpha", "Beta"])
        #expect(GraphValidator.validate(graph).isEmpty)
    }

    @Test func emptyDraftMakesAnEmptyMap() async throws {
        let map = try await capture.createMap(from: OutlineDraft(), title: "Empty")

        let graph = try #require(try await repository.loadGraph(for: map.id))
        #expect(graph.nodes.count == 1)
        #expect(graph.root?.title == "Empty")
    }

    @Test func addsUnderTheCentralTopicAfterExistingChildren() async throws {
        var engine = try GraphEngine(state: GraphState.newMap(title: "Plan"))
        let rootID = try #require(engine.state.map.rootNodeID)
        try engine.execute(AddNodeCommand(.child(of: rootID), title: "Existing"))
        try await repository.create(engine.state)

        try await capture.add(SharedContent.outline(of: [.text("New\n\tChild")]), to: engine.state.map.id)

        let graph = try #require(try await repository.loadGraph(for: engine.state.map.id))
        let children = graph.children(of: rootID)
        #expect(children.map(\.title) == ["Existing", "New"])
        #expect(children.last?.metadata.origin == .imported)
        #expect(graph.children(of: children[1].id).map(\.title) == ["Child"])
    }

    @Test func missingMapIsReported() async throws {
        await #expect(throws: QuickCapture.Failure.mapNotFound) {
            try await capture.add(OutlineDraft(items: [.init(depth: 0, title: "x")]), to: MapID())
        }
    }

    @Test func ideaGoesToTheMostRecentMap() async throws {
        let older = GraphState.newMap(title: "Older", now: Date(timeIntervalSince1970: 1))
        let newer = GraphState.newMap(title: "Newer", now: Date(timeIntervalSince1970: 2))
        try await repository.create(older)
        try await repository.create(newer)

        let map = try await capture.addIdea("  Gọi khách hàng ")

        #expect(map.id == newer.map.id)
        let graph = try #require(try await repository.loadGraph(for: newer.map.id))
        let rootID = try #require(graph.map.rootNodeID)
        let idea = try #require(graph.children(of: rootID).first)
        #expect(idea.title == "Gọi khách hàng")
        #expect(idea.metadata.origin == .user)
    }

    @Test func ideaGoesToTheChosenMap() async throws {
        let chosen = GraphState.newMap(title: "Chosen", now: Date(timeIntervalSince1970: 1))
        try await repository.create(chosen)
        try await repository.create(GraphState.newMap(title: "Newer", now: Date(timeIntervalSince1970: 2)))

        let map = try await capture.addIdea("Idea", to: chosen.map.id)

        #expect(map.id == chosen.map.id)
        #expect(map.title == "Chosen")
    }

    @Test func firstIdeaStartsAMap() async throws {
        let map = try await capture.addIdea("First idea")

        #expect(map.title == "First idea")
        #expect(try await capture.recentMaps().map(\.id) == [map.id])
    }

    @Test func blankIdeaIsRefused() async throws {
        await #expect(throws: QuickCapture.Failure.nothingToAdd) {
            try await capture.addIdea("   ")
        }
    }
}

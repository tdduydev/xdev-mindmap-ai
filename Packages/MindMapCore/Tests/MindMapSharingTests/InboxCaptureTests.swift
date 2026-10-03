import Foundation
import MindMapDomain
import MindMapGraph
import MindMapPersistence
@testable import MindMapSharing
import Synchronization
import Testing

/// The Inbox ID in memory, in place of iCloud key-value storage.
final class MemoryInboxStore: InboxMapIDStore {
    private let value = Mutex<MapID?>(nil)

    init(_ id: MapID? = nil) { value.withLock { $0 = id } }

    func inboxMapID() -> MapID? { value.withLock { $0 } }
    func setInboxMapID(_ id: MapID) { value.withLock { $0 = id } }
}

@Suite("Inbox capture")
struct InboxCaptureTests {
    let repository: SwiftDataMapRepository
    let store = MemoryInboxStore()
    let inbox: InboxCapture

    init() throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
        inbox = InboxCapture(repository: repository, store: store)
    }

    @Test func firstIdeaCreatesTheInboxAndRemembersIt() async throws {
        let map = try await inbox.addIdea("  Call the printer  ", inboxTitle: "Inbox")

        #expect(store.inboxMapID() == map.id)
        let graph = try #require(try await repository.loadGraph(for: map.id))
        #expect(graph.map.title == "Inbox")
        let rootID = try #require(graph.map.rootNodeID)
        #expect(graph.children(of: rootID).map(\.title) == ["Call the printer"])
        #expect(graph.children(of: rootID).first?.metadata.origin == .user)
        #expect(GraphValidator.validate(graph).isEmpty)
    }

    @Test func laterIdeasGoToTheSameInboxInOrder() async throws {
        let first = try await inbox.addIdea("One", inboxTitle: "Inbox")
        let second = try await inbox.addIdea("Two", inboxTitle: "Inbox")

        #expect(first.id == second.id)
        #expect(try await repository.fetchMaps().count == 1)
        let graph = try #require(try await repository.loadGraph(for: first.id))
        #expect(graph.children(of: try #require(graph.map.rootNodeID)).map(\.title) == ["One", "Two"])
    }

    @Test func anInboxSetElsewhereIsUsed() async throws {
        let other = GraphState.newMap(title: "Hộp thư")
        try await repository.create(other)
        store.setInboxMapID(other.map.id)

        let map = try await inbox.addIdea("Ý tưởng", inboxTitle: "Inbox")

        #expect(map.id == other.map.id)
    }

    @Test func aDeletedInboxIsReplaced() async throws {
        let old = try await inbox.addIdea("Old", inboxTitle: "Inbox")
        let stored = try #require(try await repository.fetchMaps().first)
        try await repository.moveToRecentlyDeleted(stored.id, at: .now)

        let new = try await inbox.addIdea("New", inboxTitle: "Inbox")

        #expect(new.id != old.id)
        #expect(store.inboxMapID() == new.id)
        let gone = MapID()
        store.setInboxMapID(gone)
        let again = try await inbox.addIdea("Again", inboxTitle: "Inbox")
        #expect(again.id != gone)
        #expect(store.inboxMapID() == again.id)
    }

    @Test func blankIdeaIsRefusedWithoutMakingAnInbox() async throws {
        await #expect(throws: QuickCapture.Failure.nothingToAdd) {
            try await inbox.addIdea(" \n ", inboxTitle: "Inbox")
        }
        #expect(store.inboxMapID() == nil)
        #expect(try await repository.fetchMaps().isEmpty)
    }

    @Test func outlineIsTheTreeInReadingOrder() async throws {
        var engine = try GraphEngine(state: GraphState.newMap(title: "Plan"))
        let rootID = try #require(engine.state.map.rootNodeID)
        try engine.execute(AddNodeCommand(.child(of: rootID), title: "A"))
        let aID = try #require(engine.state.childIDs(of: rootID).first)
        try engine.execute(AddNodeCommand(.child(of: aID), title: "A1"))
        try engine.execute(AddNodeCommand(.child(of: rootID), title: "B"))
        try await repository.create(engine.state)

        let outline = try #require(try await inbox.outline(of: engine.state.map.id))

        #expect(outline.count == 1)
        #expect(outline[0].title == "Plan")
        #expect(outline[0].children?.map(\.title) == ["A", "B"])
        #expect(outline[0].children?[0].children?.map(\.title) == ["A1"])
        #expect(outline[0].children?[1].children == nil)
    }

    @Test func outlineOfADeletedMapIsNil() async throws {
        let map = try await inbox.addIdea("Idea", inboxTitle: "Inbox")
        let stored = try #require(try await repository.fetchMaps().first)
        try await repository.moveToRecentlyDeleted(stored.id, at: .now)

        #expect(try await inbox.outline(of: map.id) == nil)
        #expect(try await inbox.recentMaps().isEmpty)
    }
}

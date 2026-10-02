import Foundation
import MindMapAICore
import MindMapDomain
import MindMapGraph
@testable import MindMapPersistence
import SwiftData
import Testing

/// Each map's saved chat (MM-55): kept per map, in order, deleted with the
/// map, cleared on request, and capped.
@Suite("Chat history", .timeLimit(.minutes(1)))
struct ChatHistoryTests {
    let container: ModelContainer
    let repository: SwiftDataMapRepository
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    init() throws {
        container = try PersistenceController.makeContainer(at: .inMemory)
        repository = SwiftDataMapRepository(modelContainer: container)
    }

    private func turn(_ question: String, in graph: GraphState) throws -> ChatTurn {
        let rootID = try #require(graph.map.rootNodeID)
        return ChatTurn(question: question, answer: "About \(question) [T1].", citations: [
            ChatCitation(handle: "T1", mapID: graph.map.id, nodeID: rootID, title: graph.map.title),
        ])
    }

    @Test func turnsComeBackInOrderWithTheirCitationsAfterReopening() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "chat-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let graph = GraphState.newMap(title: "Kế hoạch")
        let first = try turn("Đầu tiên?", in: graph)
        let second = try turn("Second", in: graph)
        let repository = try PersistenceController.makeRepository(at: .file(url))
        try await repository.create(graph)

        try await repository.appendChatTurn(first, to: graph.map.id, at: now)
        try await repository.appendChatTurn(second, to: graph.map.id, at: now.addingTimeInterval(1))

        let reopened = try PersistenceController.makeRepository(at: .file(url))
        #expect(try await reopened.chatTurns(for: graph.map.id) == [first, second])
    }

    /// MM-78 keeps the scope in `citationsData`, so the released schema stays.
    @Test func aBranchTurnKeepsItsScopeAndAWholeMapTurnStaysAPlainArray() async throws {
        let graph = GraphState.newMap(title: "Map")
        try await repository.create(graph)
        let rootID = try #require(graph.map.rootNodeID)
        var branchTurn = try turn("Branch?", in: graph)
        branchTurn.branch = ChatBranch(nodeID: rootID, title: "Plan")
        let wholeMap = try turn("Map?", in: graph)

        try await repository.appendChatTurn(branchTurn, to: graph.map.id, at: now)
        try await repository.appendChatTurn(wholeMap, to: graph.map.id, at: now.addingTimeInterval(1))

        #expect(try await repository.chatTurns(for: graph.map.id) == [branchTurn, wholeMap])
        let record = try #require(try ModelContext(container).fetch(ChatTurnRecord.withID(wholeMap.id)).first)
        let data = try #require(record.citationsData)
        #expect(try JSONDecoder().decode([ChatCitation].self, from: data) == wholeMap.citations, "MM-55 builds still read it")
    }

    @Test func eachMapKeepsItsOwnChat() async throws {
        let one = GraphState.newMap(title: "One")
        let two = GraphState.newMap(title: "Two")
        try await repository.create(one)
        try await repository.create(two)
        let asked = try turn("One?", in: one)

        try await repository.appendChatTurn(asked, to: one.map.id, at: now)

        #expect(try await repository.chatTurns(for: one.map.id) == [asked])
        #expect(try await repository.chatTurns(for: two.map.id).isEmpty)
    }

    /// Asking is not editing: the library order and the edit time stay.
    @Test func savingATurnLeavesTheMapAlone() async throws {
        let graph = GraphState.newMap(title: "Map")
        try await repository.create(graph)
        let changes = await repository.changes()

        try await repository.appendChatTurn(try turn("Q", in: graph), to: graph.map.id, at: now)
        try await repository.setFavorite(true, for: graph.map.id)

        var iterator = changes.makeAsyncIterator()
        let first = await iterator.next()
        #expect(first.map { if case .saved = $0 { true } else { false } } == true, "the favorite, not the chat, is the first change")
        #expect(try await repository.fetchMaps().first?.updatedAt == graph.map.updatedAt)
    }

    @Test func clearChatDeletesOnlyThatMapsTurns() async throws {
        let one = GraphState.newMap(title: "One")
        let two = GraphState.newMap(title: "Two")
        try await repository.create(one)
        try await repository.create(two)
        try await repository.appendChatTurn(try turn("A", in: one), to: one.map.id, at: now)
        let kept = try turn("B", in: two)
        try await repository.appendChatTurn(kept, to: two.map.id, at: now)

        try await repository.clearChat(for: one.map.id)

        #expect(try await repository.chatTurns(for: one.map.id).isEmpty)
        #expect(try await repository.chatTurns(for: two.map.id) == [kept])
    }

    @Test func deleteChatTurnDeletesOnlyThatTurn() async throws {
        let graph = GraphState.newMap(title: "Retry")
        try await repository.create(graph)
        let kept = try turn("A", in: graph)
        let replaced = try turn("B", in: graph)
        try await repository.appendChatTurn(kept, to: graph.map.id, at: now)
        try await repository.appendChatTurn(replaced, to: graph.map.id, at: now)

        try await repository.deleteChatTurn(replaced.id, from: graph.map.id)

        #expect(try await repository.chatTurns(for: graph.map.id) == [kept])
    }

    @Test func deletingTheMapDeletesItsChat() async throws {
        let graph = GraphState.newMap(title: "Gone")
        try await repository.create(graph)
        try await repository.appendChatTurn(try turn("Q", in: graph), to: graph.map.id, at: now)

        try await repository.deleteMap(graph.map.id)

        #expect(try ModelContext(container).fetchCount(FetchDescriptor<ChatTurnRecord>()) == 0)
    }

    /// Recently Deleted keeps the chat with the map; emptying it deletes both.
    @Test func recentlyDeletedKeepsTheChatUntilItIsPurged() async throws {
        let graph = GraphState.newMap(title: "Bin")
        try await repository.create(graph)
        let asked = try turn("Q", in: graph)
        try await repository.appendChatTurn(asked, to: graph.map.id, at: now)

        try await repository.moveToRecentlyDeleted(graph.map.id, at: now)
        #expect(try await repository.chatTurns(for: graph.map.id) == [asked])
        try await repository.restoreMap(graph.map.id)
        #expect(try await repository.chatTurns(for: graph.map.id) == [asked])

        try await repository.moveToRecentlyDeleted(graph.map.id, at: now)
        try await repository.purgeDeletedMaps(deletedBefore: now.addingTimeInterval(1))
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<ChatTurnRecord>()) == 0)
    }

    @Test func onlyTheLatestTurnsAreKept() async throws {
        let graph = GraphState.newMap(title: "Long")
        try await repository.create(graph)
        let limit = ChatHistory.maximumTurns
        var turns: [ChatTurn] = []
        for index in 0..<(limit + 3) {
            let next = ChatTurn(question: "Q\(index)", answer: "A\(index)", citations: [])
            turns.append(next)
            try await repository.appendChatTurn(next, to: graph.map.id, at: now.addingTimeInterval(Double(index)))
        }

        #expect(try await repository.chatTurns(for: graph.map.id) == Array(turns.suffix(limit)))
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<ChatTurnRecord>()) == limit)
    }

    /// The same turn saved again (a retry) updates the record instead of adding one.
    @Test func savingATurnTwiceKeepsOneRecord() async throws {
        let graph = GraphState.newMap(title: "Map")
        try await repository.create(graph)
        var asked = try turn("Q", in: graph)
        try await repository.appendChatTurn(asked, to: graph.map.id, at: now)
        asked.answer = "Better"

        try await repository.appendChatTurn(asked, to: graph.map.id, at: now.addingTimeInterval(5))

        #expect(try await repository.chatTurns(for: graph.map.id) == [asked])
    }

    /// A sync duplicate shows once.
    @Test func aDuplicatedTurnShowsOnce() async throws {
        let graph = GraphState.newMap(title: "Map")
        try await repository.create(graph)
        let asked = try turn("Q", in: graph)
        try await repository.appendChatTurn(asked, to: graph.map.id, at: now)
        let context = ModelContext(container)
        let copy = ChatTurnRecord(turnID: asked.id, mapID: graph.map.id.rawValue)
        try copy.update(from: asked)
        copy.createdAt = now
        context.insert(copy)
        try context.save()

        #expect(try await repository.chatTurns(for: graph.map.id) == [asked])
    }
}

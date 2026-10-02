import Foundation
import MindMapAICore
import MindMapDomain
import SwiftData

/// Each map's saved chat (MM-55, docs/chat.md). The chat is map content: it is
/// deleted with the map, syncs with it, and is never logged.
public protocol ChatHistoryStore: Sendable {
    /// The map's finished turns, oldest first, at most `ChatHistory.maximumTurns`.
    func chatTurns(for mapID: MapID) async throws -> [ChatTurn]

    /// Saves a finished turn, then drops the oldest beyond the limit. Not an
    /// edit of the map: `updatedAt` stays and no `.saved` goes out.
    func appendChatTurn(_ turn: ChatTurn, to mapID: MapID, at date: Date) async throws

    /// Clear Chat: deletes every turn of the map.
    func clearChat(for mapID: MapID) async throws
}

public enum ChatHistory {
    /// 100 turns, 200 messages counting each question and answer [Đề xuất],
    /// so a long-used map's chat cannot grow the store without bound. The
    /// model sees far fewer anyway: only the latest turns that fit its window.
    public static let maximumTurns = 100
}

extension ChatTurnRecord {
    static func inMap(_ mapID: UUID) -> FetchDescriptor<ChatTurnRecord> {
        FetchDescriptor(
            predicate: #Predicate { $0.mapID == mapID },
            sortBy: [SortDescriptor(\.createdAt), SortDescriptor(\.turnID)]
        )
    }

    static func withID(_ turnID: UUID) -> FetchDescriptor<ChatTurnRecord> {
        FetchDescriptor(predicate: #Predicate { $0.turnID == turnID })
    }

    var domainValue: ChatTurn {
        // Unreadable citations, say from a newer build, lose their chips, not the turn.
        let citations = citationsData.flatMap { try? JSONDecoder().decode([ChatCitation].self, from: $0) } ?? []
        return ChatTurn(id: turnID, question: question, answer: answer, citations: citations)
    }

    func update(from turn: ChatTurn) throws {
        question = turn.question
        answer = turn.answer
        citationsData = turn.citations.isEmpty ? nil : try JSONEncoder().encode(turn.citations)
    }
}

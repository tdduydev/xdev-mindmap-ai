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

    /// Ask Again (MM-79): deletes one turn, the answer being replaced, so a
    /// retry that stops or fails does not leave the old answer saved.
    func deleteChatTurn(_ turnID: UUID, from mapID: MapID) async throws

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
        let saved = citationsData.flatMap(SavedCitations.decode)
        return ChatTurn(id: turnID, question: question, answer: answer, citations: saved?.citations ?? [], branch: saved?.branch)
    }

    func update(from turn: ChatTurn) throws {
        question = turn.question
        answer = turn.answer
        citationsData = try SavedCitations(citations: turn.citations, branch: turn.branch).encoded()
    }
}

/// What `citationsData` holds. A whole-map turn keeps MM-55's plain array of
/// citations; a turn limited to a branch (MM-78) holds an object with the
/// branch beside them. The schema stays as released: the scope rides in the
/// JSON, and a build that knows only the array loses that turn's chips, not
/// the turn.
struct SavedCitations: Codable {
    var citations: [ChatCitation]
    var branch: ChatBranch?

    static func decode(_ data: Data) -> SavedCitations? {
        let decoder = JSONDecoder()
        if let citations = try? decoder.decode([ChatCitation].self, from: data) {
            return SavedCitations(citations: citations, branch: nil)
        }
        return try? decoder.decode(SavedCitations.self, from: data)
    }

    func encoded() throws -> Data? {
        guard let branch else { return citations.isEmpty ? nil : try JSONEncoder().encode(citations) }
        return try JSONEncoder().encode(SavedCitations(citations: citations, branch: branch))
    }
}

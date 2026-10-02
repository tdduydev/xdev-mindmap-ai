import Foundation
import MindMapDomain

// The chat (docs/chat.md, ADR 0009) as plain values: what the app shows and,
// later, saves with the map (MM-55). Only MindMapAIApple talks to the model.

/// What a conversation is about.
public enum ChatScope: Hashable, Sendable, Codable {
    /// Ask in one map (C1): its live graph, from the editor.
    case map(MapID)
}

/// A topic an answer used, resolved from a handle a tool returned.
public struct ChatCitation: Hashable, Sendable, Codable, Identifiable {
    /// The short name the model saw, such as T3.
    public let handle: String
    public let mapID: MapID
    public let nodeID: NodeID
    /// The title when the tool returned it; the topic may be renamed since.
    public let title: String

    public init(handle: String, mapID: MapID, nodeID: NodeID, title: String) {
        self.handle = handle
        self.mapID = mapID
        self.nodeID = nodeID
        self.title = title
    }

    public var id: String { handle }
}

/// One finished question and answer. Codable so MM-55 can store the
/// conversation with its map; `answer` keeps the handles, so the citations can
/// be rebuilt and an earlier turn handed back to the model as it was written.
public struct ChatTurn: Hashable, Sendable, Codable, Identifiable {
    public let id: UUID
    public var question: String
    /// The answer as the model wrote it, handles in brackets included.
    public var answer: String
    public var citations: [ChatCitation]

    public init(id: UUID = UUID(), question: String, answer: String, citations: [ChatCitation]) {
        self.id = id
        self.question = question
        self.answer = answer
        self.citations = citations
    }

    /// The answer as the panel shows it: no handles, which become chips.
    public var displayAnswer: String { CitationTable.displayText(answer) }
}

/// A question to send.
public struct ChatMessage: Hashable, Sendable {
    public var text: String
    /// The language to answer in: the question's own, else the app's.
    public var language: AILanguage
    public var userLocaleIdentifier: String

    public init(text: String, language: AILanguage, userLocaleIdentifier: String) {
        self.text = text
        self.language = language
        self.userLocaleIdentifier = userLocaleIdentifier
    }
}

/// The answer so far. Every update carries the whole text, so a consumer can
/// drop updates and still show the latest.
public struct ChatUpdate: Hashable, Sendable {
    /// What the model has written, handles included.
    public var text: String
    /// Handles cited so far that a tool returned, in the order they appear.
    public var citations: [ChatCitation]
    /// A tool is reading the map; the panel says so instead of a blank answer.
    public var isReadingMap: Bool
    /// Earlier turns were left out of what the model sees to make room.
    public var leftOutEarlierTurns: Bool
    public var isComplete: Bool

    public init(
        text: String = "",
        citations: [ChatCitation] = [],
        isReadingMap: Bool = false,
        leftOutEarlierTurns: Bool = false,
        isComplete: Bool = false
    ) {
        self.text = text
        self.citations = citations
        self.isReadingMap = isReadingMap
        self.leftOutEarlierTurns = leftOutEarlierTurns
        self.isComplete = isComplete
    }
}

/// A source of chat conversations, beside `AIProvider` so neither grows for
/// the other. Like every AI provider, it reads but never changes a map.
public protocol ChatProvider: Sendable {
    func capabilities() async -> AICapabilities

    /// A new conversation. `history` is what an earlier one left (MM-55), so
    /// its citations keep working and the model sees as much of it as fits.
    func conversation(in scope: ChatScope, history: [ChatTurn]) -> any ChatConversation
}

/// One conversation: the model keeps its earlier turns. One question at a
/// time; cancelling the consuming task stops the answer.
public protocol ChatConversation: AnyObject, Sendable {
    /// Throws `AIError` (or `CancellationError`); the last update is complete.
    func send(_ message: ChatMessage) -> AsyncThrowingStream<ChatUpdate, any Error>
}

extension AICapabilities {
    /// Whether the chat can answer in `language`. The chat uses the same model
    /// as every other AI feature, so the same rules apply.
    public func chatAvailability(in language: AILanguage) -> AIAvailability {
        guard model == .ready else { return model }
        return supportedLanguages.contains(language) ? .ready : .languageUnsupported
    }
}

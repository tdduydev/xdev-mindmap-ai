import Foundation
import MindMapDomain
import MindMapGraph

/// Turns what was said into topic titles: one topic per sentence (FR-AI-21).
public enum SpokenTopics {
    /// Sentence ends: the punctuation transcribers write, Latin and CJK.
    private static let terminators: Set<Character> = [".", "!", "?", "…", "。", "！", "？"]
    /// Japanese writes no space after a sentence, so these end one wherever they are.
    private static let fullWidthTerminators: Set<Character> = ["。", "！", "？"]

    /// Splits at a sentence end followed by a space or the end of the text, so
    /// "3.5" and "v2.0" stay whole; a full-width end splits even with no space.
    /// A closing period is dropped, since a topic is a heading rather than a
    /// sentence; "?" and "!" carry meaning and stay.
    public static func titles(from text: String) -> [String] {
        var titles: [String] = []
        var current = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if character.isNewline {
                append(current, to: &titles)
                current = ""
            } else {
                current.append(character)
                if fullWidthTerminators.contains(character)
                    || terminators.contains(character) && (next == text.endIndex || text[next].isWhitespace) {
                    append(current, to: &titles)
                    current = ""
                }
            }
            index = next
        }
        append(current, to: &titles)
        return titles
    }

    private static func append(_ sentence: String, to titles: inout [String]) {
        var title = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = title.last, last == "." || last == "。" || last == "…" {
            title.removeLast()
        }
        title = title.trimmingCharacters(in: .whitespaces)
        // Punctuation alone ("?") is not a topic.
        guard title.contains(where: { $0.isLetter || $0.isNumber }) else { return }
        titles.append(title)
    }

    /// Adds `titles` as the last children of `parentID`, in order, as one
    /// command so the whole dictation is one undo step. IDs are picked here,
    /// so the caller can select the new topics and redo recreates the same ones.
    public static func command(adding titles: [String], under parentID: NodeID) -> (command: BatchCommand, nodeIDs: [NodeID]) {
        let ids = titles.map { _ in NodeID() }
        let commands = zip(ids, titles).map { id, title in
            AddNodeCommand(nodeID: id, .child(of: parentID), title: title)
        }
        return (BatchCommand(commands), ids)
    }
}

/// What has been heard so far in one dictation: the topics, which the user can
/// edit or remove before adding them, and the words still being recognized.
public struct VoiceTranscript: Hashable, Sendable {
    public struct Topic: Identifiable, Hashable, Sendable {
        public let id: UUID
        public var title: String

        public init(id: UUID = UUID(), title: String) {
            self.id = id
            self.title = title
        }
    }

    public var topics: [Topic] = []
    /// Not final yet; shown apart and never added as a topic.
    public private(set) var pending = ""

    public init(topics: [Topic] = []) {
        self.topics = topics
    }

    public mutating func apply(_ update: VoiceTranscriptUpdate) {
        switch update {
        case .volatile(let text):
            pending = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .final(let text):
            pending = ""
            topics += SpokenTopics.titles(from: text).map { Topic(title: $0) }
        }
    }

    /// The titles to add: edited text, trimmed, empty ones left out.
    public var titles: [String] {
        topics
            .map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public var isEmpty: Bool { topics.isEmpty && pending.isEmpty }
}

import Foundation
import MindMapDomain
import NaturalLanguage

/// Topics the chat suggests under one topic (docs/chat.md, C2, MM-51): from
/// the model's `suggestTopics` tool or from Create Topics from Answer. Like
/// every AI suggestion it changes nothing; the app shows it in
/// `SuggestionState`, and only Accept turns it into a command.
public struct ChatSuggestion: Hashable, Sendable {
    /// Topics per suggestion [Đề xuất]: as many as Brainstorm, so the
    /// preview stays readable and the tool output stays short.
    public static let maximumTopics = 8

    /// The real topic the suggestions hang under.
    public let parentID: NodeID
    /// Its title when suggested, for the line the panel shows.
    public let parentTitle: String
    /// Pre-order, parents first; temporary IDs c1, c2…
    public let topics: [ProposedTopic]

    public init?(parentID: NodeID, parentTitle: String, topics: [ProposedTopic]) {
        guard !topics.isEmpty else { return nil }
        self.parentID = parentID
        self.parentTitle = parentTitle
        self.topics = topics
    }

    /// The suggestion as an AI proposal, checked by `ProposalTranslator` on Accept.
    public var proposal: AIProposal {
        AIProposal(feature: .chat, anchor: .node(parentID), topics: topics)
    }

    // MARK: From the tool

    /// One level of topics from the titles the model gave: trimmed, one line,
    /// repeats and titles already among `existingTitles` left out, at most
    /// `maximumTopics`. Nil when nothing is left.
    public init?(titles: [String], under parentID: NodeID, parentTitle: String, existingTitles: [String] = []) {
        var seen = Set(existingTitles.map(Self.key))
        var topics: [ProposedTopic] = []
        for raw in titles {
            let title = Self.oneLine(raw)
            guard !title.isEmpty, seen.insert(Self.key(title)).inserted else { continue }
            topics.append(ProposedTopic(temporaryID: "c\(topics.count + 1)", title: title))
            if topics.count == Self.maximumTopics { break }
        }
        self.init(parentID: parentID, parentTitle: parentTitle, topics: topics)
    }

    // MARK: From an answer

    /// Topics read from an answer's text, without the model: each list item
    /// becomes a topic, an indented item a subtopic of the item above it;
    /// an answer without a list gives one topic per sentence. Handles and
    /// Markdown emphasis are left out. Nil when the answer holds no text.
    public init?(answer: String, under parentID: NodeID, parentTitle: String) {
        let text = CitationTable.displayText(answer)
        let items = Self.listItems(in: text)
        var topics: [ProposedTopic] = []
        if items.isEmpty {
            for sentence in Self.sentences(in: text).prefix(Self.maximumTopics) {
                topics.append(ProposedTopic(temporaryID: "c\(topics.count + 1)", title: sentence))
            }
        } else {
            // Items in reading order, so a prefix never keeps a child without its parent.
            var open: [(indent: Int, id: String)] = []
            for item in items.prefix(Self.maximumTopics) {
                while let last = open.last, last.indent >= item.indent { open.removeLast() }
                let id = "c\(topics.count + 1)"
                topics.append(ProposedTopic(temporaryID: id, parentTemporaryID: open.last?.id, title: item.title))
                open.append((item.indent, id))
            }
        }
        self.init(parentID: parentID, parentTitle: parentTitle, topics: topics)
    }

    // MARK: Helpers

    private struct ListItem {
        let indent: Int
        let title: String
    }

    nonisolated(unsafe) private static let bullet = /^([ \t]*)(?:[-*+•–]|\d{1,3}[.)])[ \t]+(.+)$/

    private static func listItems(in text: String) -> [ListItem] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            guard let match = String(line).wholeMatch(of: bullet) else { return nil }
            let indent = match.1.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
            let title = cleaned(String(match.2))
            return title.isEmpty ? nil : ListItem(indent: indent, title: title)
        }
    }

    private static func sentences(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex).compactMap { range in
            var sentence = cleaned(String(text[range]))
            while let last = sentence.last, ".。!！".contains(last) { sentence.removeLast() }
            return sentence.isEmpty ? nil : sentence
        }
    }

    /// One line without Markdown emphasis or heading marks.
    private static func cleaned(_ text: String) -> String {
        var result = text.replacing("**", with: "").replacing("__", with: "").replacing("`", with: "")
        result = String(result.drop { $0 == "#" })
        return oneLine(result)
    }

    private static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func key(_ title: String) -> String {
        oneLine(title).folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
    }
}

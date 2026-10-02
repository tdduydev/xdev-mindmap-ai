import Foundation
import MindMapAICore
import MindMapDomain
import MindMapQuery
import Synchronization

/// What the chat's tools read from one map, written as short text for the
/// model, topics named by handle (T1, T2…) rather than by UUID.
///
/// Plain text and no FoundationModels, so tests check it without a model.
/// Every result is cut to the budget's tool output; nothing here logs, since
/// every argument and result is map content (docs/privacy.md).
final class ChatMapReader: Sendable {
    /// Hits per search before the budget cuts them.
    static let searchLimit = 8
    /// Path titles shown for a hit, nearest last.
    static let pathLength = 3
    static let maximumDepth = 3
    /// What the map line and the closing "more topics" lines of an outline cost.
    static let outlineFrame = 80

    let queries: MapQueries
    let mapID: MapID
    private let table: Mutex<CitationTable>
    private let toolOutput: Mutex<Int>

    init(queries: MapQueries, mapID: MapID, toolOutput: Int, table: CitationTable = CitationTable()) {
        self.queries = queries
        self.mapID = mapID
        self.toolOutput = Mutex(toolOutput)
        self.table = Mutex(table)
    }

    /// What one result may cost, in estimated tokens. A handle, a bullet and
    /// the indentation cost a few tokens per topic.
    var limit: TextLimit {
        TextLimit(budget: toolOutput.withLock { $0 }, perTopic: 4, measure: TokenEstimator.estimate)
    }

    func setToolOutput(_ tokens: Int) {
        toolOutput.withLock { $0 = tokens }
    }

    /// The map's title for the prompt, or an empty string when it is gone.
    func mapTitle() async -> String {
        let outline = try? await queries.outline(of: mapID, depth: 0, includeNotes: false, limit: .characters(1))
        return outline.map { MapQueries.oneLine($0.mapTitle) } ?? ""
    }

    var citationTable: CitationTable {
        table.withLock { $0 }
    }

    func replaceCitationTable(_ newTable: CitationTable) {
        table.withLock { $0 = newTable }
    }

    // MARK: Tools

    func searchTopics(_ text: String) async -> String {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return "Give a few words to search for." }
        do {
            let hits = try await queries.search(query, in: mapID, limit: Self.searchLimit)
            guard !hits.isEmpty else {
                return "No topic matches \(Self.quoted(query)). Try other words, or readBranch with an empty handle for the whole map."
            }
            let limit = self.limit
            var lines = ["Topics matching \(Self.quoted(query)):"]
            var remaining = limit.budget - limit.cost(lines[0])
            var shown = 0
            for hit in hits {
                let handle = handle(for: hit.ref.nodeID, title: hit.title)
                var line = "- \(handle): \(hit.title)"
                let path = hit.path.suffix(Self.pathLength)
                if !path.isEmpty { line += " (under \(path.joined(separator: " > ")))" }
                if let excerpt = hit.excerpt { line += "\n  note: \(excerpt)" }
                let cost = limit.cost(line) + limit.perTopic
                guard cost <= remaining else { break }
                remaining -= cost
                lines.append(line)
                shown += 1
            }
            if shown < hits.count { lines.append("(\(hits.count - shown) more matches not shown; search with more words.)") }
            return lines.joined(separator: "\n")
        } catch {
            return Self.failure(error)
        }
    }

    func readTopic(_ handle: String) async -> String {
        guard let citation = citationTable.citation(for: handle) else { return Self.unknownHandle(handle) }
        do {
            guard let topic = try await queries.topic(TopicRef(mapID: citation.mapID, nodeID: citation.nodeID)) else {
                return "Topic \(citation.handle) no longer exists."
            }
            let ownHandle = self.handle(for: topic.ref.nodeID, title: MapQueries.oneLine(topic.title))
            var lines = ["\(ownHandle): \(MapQueries.oneLine(topic.title))"]
            if !topic.path.isEmpty {
                lines.append("Path: " + topic.path.map { "\(self.handle(for: $0.nodeID, title: $0.title)) \($0.title)" }.joined(separator: " > "))
            }
            if !topic.children.isEmpty {
                lines.append("Subtopics: " + topic.children.map { "\(self.handle(for: $0.nodeID, title: $0.title)) \($0.title)" }.joined(separator: "; "))
            }
            if !topic.tags.isEmpty { lines.append("Tags: " + topic.tags.joined(separator: ", ")) }
            if let state = topic.taskState { lines.append("Task: " + (state.isDone ? "done" : "open")) }
            if let priority = topic.priority { lines.append("Priority: " + Self.name(of: priority)) }
            if let start = topic.startDate { lines.append("Starts: \(start.isoString)") }
            if let due = topic.dueDate { lines.append("Due: \(due.isoString)") }
            for link in topic.crossLinks {
                let other = "\(self.handle(for: link.topic.nodeID, title: link.topic.title)) \(link.topic.title)"
                let label = link.label.map { " (\(Self.quoted($0)))" } ?? ""
                lines.append((link.direction == .outgoing ? "Links to " : "Linked from ") + other + label)
            }
            // The note goes last and takes what the budget leaves, so the
            // structure always shows.
            let limit = self.limit
            var text = Self.fitting(lines, in: limit)
            if let note = topic.note {
                let remaining = limit.budget - limit.cost(text) - limit.cost("Note: ")
                let cut = limit.prefix(of: note, fitting: remaining)
                if !cut.isEmpty { text += "\nNote: " + cut + (cut.count < note.count ? " (note cut)" : "") }
            }
            return text
        } catch {
            return Self.failure(error)
        }
    }

    /// `handle` empty reads from the central topic.
    func readBranch(_ handle: String, depth: Int) async -> String {
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        var branch: NodeID?
        if !trimmed.isEmpty {
            guard let citation = citationTable.citation(for: trimmed) else { return Self.unknownHandle(trimmed) }
            branch = citation.nodeID
        }
        do {
            // In Vietnamese every character is a token, so the indentation,
            // bullet and handle of each row count, and the header and the
            // "more topics" lines get their share up front.
            let budget = limit.budget
            let outline = try await queries.outline(
                of: mapID,
                branch: branch,
                depth: min(max(1, depth), Self.maximumDepth),
                limit: TextLimit(budget: budget - Self.outlineFrame, perTopic: 14, measure: TokenEstimator.estimate)
            )
            var lines = ["Map: \(MapQueries.oneLine(outline.mapTitle))"]
            for topic in outline.topics {
                let indent = String(repeating: "  ", count: topic.depth)
                lines.append("\(indent)- \(self.handle(for: topic.nodeID, title: topic.title)): \(topic.title)")
                if let note = topic.note {
                    let oneLine = MapQueries.oneLine(note)
                    lines.append("\(indent)  note: \(oneLine)\(topic.isNoteCut ? " (note cut)" : "")")
                }
            }
            if outline.omittedTopicCount > 0 {
                lines.append("(\(outline.omittedTopicCount) more topics not shown; read a subtopic to see them.)")
            }
            if outline.deeperTopicCount > 0 {
                lines.append("(\(outline.deeperTopicCount) topics deeper down; read a subtopic to see them.)")
            }
            return lines.joined(separator: "\n")
        } catch MapQueryError.topicNotFound {
            return "Topic \(trimmed) no longer exists."
        } catch {
            return Self.failure(error)
        }
    }

    // MARK: Helpers

    private func handle(for nodeID: NodeID, title: String) -> String {
        table.withLock { $0.handle(for: nodeID, in: mapID, title: title) }
    }

    /// The lines that fit, in order; the first always does.
    private static func fitting(_ lines: [String], in limit: TextLimit) -> String {
        var kept: [String] = []
        var remaining = limit.budget
        for line in lines {
            let cost = limit.cost(line) + 1
            guard kept.isEmpty || cost <= remaining else { break }
            kept.append(line)
            remaining -= cost
        }
        return kept.joined(separator: "\n")
    }

    static func unknownHandle(_ handle: String) -> String {
        "There is no topic \(handle). Use a handle that searchTopics or readBranch returned."
    }

    private static func failure(_ error: any Error) -> String {
        if case MapQueryError.mapNotFound? = error as? MapQueryError {
            return "This map is no longer available."
        }
        // A store error: no description, which may quote content.
        return "The map could not be read just now."
    }

    private static func quoted(_ text: String) -> String {
        "\u{201C}\(MapQueries.oneLine(text))\u{201D}"
    }

    private static func name(of priority: TaskPriority) -> String {
        switch priority.level {
        case .high: "high"
        case .medium: "medium"
        default: "low"
        }
    }
}

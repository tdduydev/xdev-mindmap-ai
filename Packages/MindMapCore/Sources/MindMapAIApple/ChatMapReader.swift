import Foundation
import MindMapAICore
import MindMapDomain
import MindMapQuery
import Synchronization

/// What the chat's tools read from one map, or from the whole library (C3),
/// written as short text for the model, topics named by handle (T1, T2…) and
/// maps by handle (M1, M2…) rather than by UUID.
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
    /// Maps per listMaps before the budget cuts them.
    static let mapListLimit = 20

    let queries: MapQueries
    /// The map the chat is about; nil for the whole library.
    let mapID: MapID?
    private let table: Mutex<CitationTable>
    private let toolOutput: Mutex<Int>
    /// The branch this question is limited to (MM-78), nil for the whole map.
    private let branch = Mutex<NodeID?>(nil)
    /// The library's map handles (M1, M2…). Never citations: a citation opens
    /// a topic, and the model reaches a map's topics through readBranch.
    private let maps = Mutex<[MapID]>([])

    init(queries: MapQueries, mapID: MapID?, toolOutput: Int, table: CitationTable = CitationTable()) {
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

    /// Set before each question: every tool then reads only this branch, and a
    /// handle from earlier in the conversation that lies outside it is refused.
    func setBranch(_ nodeID: NodeID?) {
        branch.withLock { $0 = nodeID }
    }

    var currentBranch: NodeID? {
        branch.withLock { $0 }
    }

    /// The map's title for the prompt, or an empty string when it is gone.
    func mapTitle() async -> String {
        guard let mapID else { return "" }
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
            let branch = currentBranch
            let hits = try await queries.search(query, in: mapID, under: branch, limit: Self.searchLimit)
            guard !hits.isEmpty else {
                guard mapID != nil else {
                    return "No topic in any map matches \(Self.quoted(query)). Try other words, or listMaps to see the maps."
                }
                let whole = branch == nil ? "the whole map" : "the whole branch"
                return "No topic matches \(Self.quoted(query)). Try other words, or readBranch with an empty handle for \(whole)."
            }
            let limit = self.limit
            var lines = ["Topics matching \(Self.quoted(query)):"]
            var remaining = limit.budget - limit.cost(lines[0])
            var shown = 0
            for hit in hits {
                let handle = handle(for: hit.ref.nodeID, in: hit.ref.mapID, title: hit.title)
                var line = "- \(handle): \(hit.title)"
                let path = hit.path.suffix(Self.pathLength)
                // Across the library the map says where the topic is.
                if mapID == nil {
                    let place = "\(mapHandle(for: hit.ref.mapID)) \(MapQueries.oneLine(hit.mapTitle))"
                    line += path.isEmpty ? " (map \(place))" : " (map \(place), under \(path.joined(separator: " > ")))"
                } else if !path.isEmpty {
                    line += " (under \(path.joined(separator: " > ")))"
                }
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
            if let branch = currentBranch, !Self.topic(topic, isIn: branch) { return Self.outsideBranch(citation.handle) }
            let mapID = citation.mapID
            let ownHandle = self.handle(for: topic.ref.nodeID, in: mapID, title: MapQueries.oneLine(topic.title))
            var lines = ["\(ownHandle): \(MapQueries.oneLine(topic.title))"]
            if !topic.path.isEmpty {
                lines.append("Path: " + topic.path.map { "\(self.handle(for: $0.nodeID, in: mapID, title: $0.title)) \($0.title)" }.joined(separator: " > "))
            }
            if !topic.children.isEmpty {
                lines.append("Subtopics: " + topic.children.map { "\(self.handle(for: $0.nodeID, in: mapID, title: $0.title)) \($0.title)" }.joined(separator: "; "))
            }
            if !topic.tags.isEmpty { lines.append("Tags: " + topic.tags.joined(separator: ", ")) }
            if let state = topic.taskState { lines.append("Task: " + (state.isDone ? "done" : "open")) }
            if let priority = topic.priority { lines.append("Priority: " + Self.name(of: priority)) }
            if let start = topic.startDate { lines.append("Starts: \(start.isoString)") }
            if let due = topic.dueDate { lines.append("Due: \(due.isoString)") }
            for link in topic.crossLinks {
                let other = "\(self.handle(for: link.topic.nodeID, in: mapID, title: link.topic.title)) \(link.topic.title)"
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

    /// `handle` empty reads from the central topic. Across the library it
    /// takes a map handle (M2) for the whole map or a topic handle (T3).
    func readBranch(_ handle: String, depth: Int) async -> String {
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        let scope = currentBranch
        var branch = scope
        var mapID = self.mapID
        do {
            if self.mapID == nil, let listed = self.map(for: trimmed) {
                mapID = listed
            } else if self.mapID == nil, trimmed.isEmpty {
                return "Give the handle of a map from listMaps, such as M1, or of a topic, such as T3."
            } else if !trimmed.isEmpty {
                guard let citation = citationTable.citation(for: trimmed) else { return Self.unknownHandle(trimmed) }
                if let scope {
                    guard let topic = try await queries.topic(TopicRef(mapID: citation.mapID, nodeID: citation.nodeID)) else {
                        return "Topic \(citation.handle) no longer exists."
                    }
                    guard Self.topic(topic, isIn: scope) else { return Self.outsideBranch(citation.handle) }
                }
                branch = citation.nodeID
                mapID = citation.mapID
            }
            guard let mapID else { return Self.unknownHandle(trimmed) }
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
            let mapLine = self.mapID == nil ? "Map \(mapHandle(for: mapID)): " : "Map: "
            var lines = [mapLine + MapQueries.oneLine(outline.mapTitle)]
            for topic in outline.topics {
                let indent = String(repeating: "  ", count: topic.depth)
                lines.append("\(indent)- \(self.handle(for: topic.nodeID, in: mapID, title: topic.title)): \(topic.title)")
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
        } catch MapQueryError.mapNotFound where self.mapID == nil {
            return "Map \(trimmed) is no longer in the library."
        } catch MapQueryError.topicNotFound {
            return "Topic \(trimmed) no longer exists."
        } catch {
            return Self.failure(error)
        }
    }

    /// Across the library only (C3): the live maps whose titles match,
    /// most recently edited first, each with a map handle.
    func listMaps(_ text: String) async -> String {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let listings = try await queries.maps(matching: query, limit: Self.mapListLimit)
            guard !listings.isEmpty else {
                return query.isEmpty ? "The library has no maps." : "No map title matches \(Self.quoted(query)). Try listMaps with an empty query for every map."
            }
            let limit = self.limit
            var lines = [query.isEmpty ? "Maps, most recently edited first:" : "Maps matching \(Self.quoted(query)):"]
            var remaining = limit.budget - limit.cost(lines[0])
            var shown = 0
            for listing in listings {
                let line = "- \(mapHandle(for: listing.mapID)): \(MapQueries.oneLine(listing.title)) (\(listing.topicCount) topics)"
                let cost = limit.cost(line) + limit.perTopic
                guard cost <= remaining else { break }
                remaining -= cost
                lines.append(line)
                shown += 1
            }
            if shown < listings.count { lines.append("(More maps not shown; list with words from a title.)") }
            return lines.joined(separator: "\n")
        } catch {
            return Self.failure(error)
        }
    }

    // MARK: Helpers

    private func handle(for nodeID: NodeID, in mapID: MapID, title: String) -> String {
        table.withLock { $0.handle(for: nodeID, in: mapID, title: title) }
    }

    /// The map's handle, the same one each time it comes up.
    func mapHandle(for mapID: MapID) -> String {
        maps.withLock { maps in
            if let index = maps.firstIndex(of: mapID) { return "M\(index + 1)" }
            maps.append(mapID)
            return "M\(maps.count)"
        }
    }

    /// Nil for anything but a map handle a tool returned.
    func map(for handle: String) -> MapID? {
        let compact = handle.filter { !$0.isWhitespace }
        guard compact.first == "M" || compact.first == "m", let number = Int(compact.dropFirst()), number > 0 else { return nil }
        return maps.withLock { number <= $0.count ? $0[number - 1] : nil }
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

    private static func topic(_ topic: TopicDetail, isIn branch: NodeID) -> Bool {
        topic.ref.nodeID == branch || topic.path.contains { $0.nodeID == branch }
    }

    static func outsideBranch(_ handle: String) -> String {
        "Topic \(handle) is outside the branch this question is about. Use searchTopics or readBranch to read inside the branch."
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

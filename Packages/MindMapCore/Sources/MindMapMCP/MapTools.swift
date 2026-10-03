import Foundation
import MindMapDomain
import MindMapQuery

/// What a tool call gives back: Markdown for the model, the same data as JSON
/// for clients that read `structuredContent`.
struct ToolResult: Sendable, Equatable {
    var text: String
    var structured: JSONValue?
    var isError = false

    static func failure(_ message: String) -> ToolResult {
        ToolResult(text: message, structured: nil, isError: true)
    }
}

/// The read tools and, when the app takes proposals, `propose_topics`
/// (docs/mcp.md, Tools and resources). Every argument and result is map
/// content, so nothing here logs.
struct MapTools: Sendable {
    enum CallError: Error, Equatable {
        case unknownTool
    }

    /// A wrong argument. Reported to the model as a tool error, so it can fix
    /// the call itself (2026-07-28, Tools: Error Handling).
    struct InputError: Error {
        let message: String
    }

    let queries: MapQueries
    /// Characters of Markdown per result, so one big map does not fill the
    /// client's context; `get_map` with `topic_id` and `depth` reads the rest.
    let outputLimit: Int
    /// Nil in a server that only reads (the dev server, most tests): then
    /// `propose_topics` is neither listed nor callable.
    var proposals: (any MCPProposalReceiver)?

    static let readNames = ["list_maps", "get_map", "search", "get_topic"]

    var names: [String] { Self.readNames + (proposals == nil ? [] : ["propose_topics"]) }

    var definitions: [JSONValue] { Self.definitions + (proposals == nil ? [] : [Self.proposeTopicsDefinition]) }

    func call(_ name: String, arguments: [String: JSONValue], client: MCPClient) async throws(CallError) -> ToolResult {
        let arguments = Arguments(values: arguments)
        do {
            let result: ToolResult
            switch name {
            case "list_maps": result = try await listMaps(arguments)
            case "get_map": result = try await getMap(arguments)
            case "search": result = try await search(arguments)
            case "get_topic": result = try await getTopic(arguments)
            case "propose_topics": result = try await proposeTopics(arguments, client: client)
            default: throw CallError.unknownTool
            }
            return result.limited(to: outputLimit)
        } catch let error as CallError {
            throw error
        } catch let error as InputError {
            return .failure(error.message)
        } catch MapQueryError.mapNotFound {
            return .failure(Self.mapNotFound)
        } catch MapQueryError.topicNotFound {
            return .failure(Self.topicNotFound)
        } catch {
            // A store error: say so without its description, which may quote content.
            return .failure("MindMap AI could not read its library just now. Try again in a moment.")
        }
    }

    static let mapNotFound = "No live map has that map_id. It may have been deleted or moved to Recently Deleted; call list_maps for current IDs."
    static let topicNotFound = "That map has no topic with this topic_id. Call get_map for the map's current topic IDs."

    // MARK: list_maps

    private func listMaps(_ arguments: Arguments) async throws -> ToolResult {
        let limit = try arguments.int("limit", default: 50, in: 1...200)
        let query = try arguments.string("query")
        let maps = try await queries.maps(matching: query, limit: limit)

        var lines = [maps.isEmpty
            ? (query == nil ? "There are no maps yet." : "No map title matches \(Self.quoted(query ?? "")).")
            : "\(Self.count(maps.count, "map")), most recently edited first:"]
        for map in maps {
            lines.append("- \(Self.inline(map.title)) (map_id: \(map.mapID), \(Self.count(map.topicCount, "topic")), edited \(Self.timestamp(map.updatedAt)))")
        }
        let structured: JSONValue = ["maps": .array(maps.map {
            ["map_id": .string($0.mapID.description), "title": .string($0.title),
             "topic_count": .int($0.topicCount), "updated_at": .string(Self.timestamp($0.updatedAt))]
        })]
        return ToolResult(text: lines.joined(separator: "\n"), structured: structured)
    }

    // MARK: get_map

    private func getMap(_ arguments: Arguments) async throws -> ToolResult {
        let mapID = try arguments.mapID("map_id")
        let branch = try arguments.nodeID("topic_id")
        let depth = try arguments.optionalInt("depth", in: 0...1_000)
        let includeNotes = try arguments.bool("include_notes", default: true)
        // Room for the heading and the closing lines, and per topic for the
        // bullet, indentation and the ID comment.
        let limit = TextLimit.characters(max(0, outputLimit - 600), perTopic: 64)
        let outline = try await queries.outline(of: mapID, branch: branch, depth: depth, includeNotes: includeNotes, limit: limit)

        var lines = ["# \(Self.inline(outline.mapTitle)) (map_id: \(outline.mapID))", ""]
        for topic in outline.topics {
            let indent = String(repeating: "  ", count: topic.depth)
            let floating = topic.isFloating ? " (floating topic)" : ""
            lines.append("\(indent)- \(Self.inline(topic.title))\(floating) <!-- topic_id: \(topic.nodeID) -->")
            if let note = topic.note {
                for noteLine in note.split(separator: "\n", omittingEmptySubsequences: false) {
                    lines.append("\(indent)  \(noteLine)".trimmingTrailingSpaces())
                }
                if topic.isNoteCut { lines.append("\(indent)  … (note cut; call get_topic for all of it)") }
            }
        }
        if outline.omittedTopicCount > 0 {
            lines += ["", "\(Self.count(outline.omittedTopicCount, "more topic")) did not fit. Call get_map with topic_id (a branch) and depth to read them."]
        }
        if outline.deeperTopicCount > 0 {
            lines += ["", "\(Self.count(outline.deeperTopicCount, "topic")) below depth \(depth ?? 0) not shown."]
        }
        let structured: JSONValue = [
            "map_id": .string(outline.mapID.description),
            "map_title": .string(outline.mapTitle),
            "topics": .array(outline.topics.map { topic in
                var row: [String: JSONValue] = [
                    "topic_id": .string(topic.nodeID.description), "depth": .int(topic.depth),
                    "title": .string(topic.title), "child_count": .int(topic.childCount),
                ]
                if let note = topic.note { row["note"] = .string(note) }
                if topic.isNoteCut { row["note_cut"] = true }
                if topic.isFloating { row["floating"] = true }
                return .object(row)
            }),
            "omitted_topic_count": .int(outline.omittedTopicCount),
            "deeper_topic_count": .int(outline.deeperTopicCount),
        ]
        return ToolResult(text: lines.joined(separator: "\n"), structured: structured)
    }

    // MARK: search

    private func search(_ arguments: Arguments) async throws -> ToolResult {
        guard let text = try arguments.string("query"), !text.allSatisfy(\.isWhitespace) else {
            throw InputError(message: "search needs a non-empty query.")
        }
        let mapID = try arguments.optionalMapID("map_id")
        let limit = try arguments.int("limit", default: 20, in: 1...50)
        let hits = try await queries.search(text, in: mapID, limit: limit)

        var lines = [hits.isEmpty
            ? "No topic matches \(Self.quoted(text))."
            : "\(Self.count(hits.count, "topic")) match \(Self.quoted(text)), title matches first:"]
        for (index, hit) in hits.enumerated() {
            let path = (hit.path.isEmpty ? [] : [hit.path.map(Self.inline).joined(separator: " › ")])
            lines.append("\(index + 1). \(Self.inline(hit.title)) (map: \(Self.inline(hit.mapTitle)); map_id: \(hit.ref.mapID), topic_id: \(hit.ref.nodeID))")
            if let path = path.first { lines.append("   Path: \(path)") }
            if let excerpt = hit.excerpt { lines.append("   Note: \(Self.inline(excerpt))") }
        }
        let structured: JSONValue = ["hits": .array(hits.map { hit in
            var row: [String: JSONValue] = [
                "map_id": .string(hit.ref.mapID.description), "topic_id": .string(hit.ref.nodeID.description),
                "map_title": .string(hit.mapTitle), "title": .string(hit.title),
                "path": .array(hit.path.map(JSONValue.string)), "match": hit.match == .title ? "title" : "note",
            ]
            if let excerpt = hit.excerpt { row["excerpt"] = .string(excerpt) }
            return .object(row)
        })]
        return ToolResult(text: lines.joined(separator: "\n"), structured: structured)
    }

    // MARK: get_topic

    private func getTopic(_ arguments: Arguments) async throws -> ToolResult {
        let ref = TopicRef(mapID: try arguments.mapID("map_id"), nodeID: try arguments.requiredNodeID("topic_id"))
        guard let topic = try await queries.topic(ref) else {
            // Tell the two apart, so the model knows whether to list maps or reread the map.
            let isMapLive = try await queries.maps(matching: nil, limit: .max).contains { $0.mapID == ref.mapID }
            return .failure(isMapLive ? Self.topicNotFound : Self.mapNotFound)
        }
        let summary = { (item: TopicSummary) in "\(Self.inline(item.title)) (topic_id: \(item.nodeID))" }
        var lines = ["# \(Self.inline(topic.title))", "", "- Map: \(Self.inline(topic.mapTitle)) (map_id: \(ref.mapID))", "- topic_id: \(ref.nodeID)"]
        if !topic.path.isEmpty { lines.append("- Path: " + topic.path.map { Self.inline($0.title) }.joined(separator: " › ")) }
        if let state = topic.taskState { lines.append("- Task: \(state.rawValue)") }
        if let priority = topic.priority { lines.append("- Priority: \(Self.name(of: priority))") }
        if let start = topic.startDate { lines.append("- Start: \(start.isoString)") }
        if let due = topic.dueDate { lines.append("- Due: \(due.isoString)") }
        if !topic.tags.isEmpty { lines.append("- Tags: " + topic.tags.map(Self.inline).joined(separator: ", ")) }
        if let note = topic.note { lines += ["", "## Note", "", note] }
        if !topic.children.isEmpty {
            lines += ["", "## Subtopics", ""] + topic.children.map { "- " + summary($0) }
        }
        if !topic.crossLinks.isEmpty {
            lines += ["", "## Cross-links", ""] + topic.crossLinks.map { link in
                let arrow = link.direction == .outgoing ? "→" : "←"
                return "- \(arrow) \(summary(link.topic))" + (link.label.map { " — \(Self.inline($0))" } ?? "")
            }
        }

        let item = { (item: TopicSummary) -> JSONValue in ["topic_id": .string(item.nodeID.description), "title": .string(item.title)] }
        var structured: [String: JSONValue] = [
            "map_id": .string(ref.mapID.description), "topic_id": .string(ref.nodeID.description),
            "map_title": .string(topic.mapTitle), "title": .string(topic.title),
            "path": .array(topic.path.map(item)), "children": .array(topic.children.map(item)),
            "tags": .array(topic.tags.map(JSONValue.string)),
            "cross_links": .array(topic.crossLinks.map { link in
                var row: [String: JSONValue] = [
                    "topic_id": .string(link.topic.nodeID.description), "title": .string(link.topic.title),
                    "direction": link.direction == .outgoing ? "outgoing" : "incoming",
                ]
                if let label = link.label { row["label"] = .string(label) }
                return .object(row)
            }),
        ]
        if let note = topic.note { structured["note"] = .string(note) }
        if let state = topic.taskState { structured["task_state"] = .string(state.rawValue) }
        if let priority = topic.priority { structured["priority"] = .string(Self.name(of: priority)) }
        if let start = topic.startDate { structured["start_date"] = .string(start.isoString) }
        if let due = topic.dueDate { structured["due_date"] = .string(due.isoString) }
        return ToolResult(text: lines.joined(separator: "\n"), structured: .object(structured))
    }

    // MARK: Formatting

    /// Titles stay on one line in every list.
    static func inline(_ text: String) -> String {
        text.split(omittingEmptySubsequences: true) { $0.isNewline }.joined(separator: " ")
    }

    static func quoted(_ text: String) -> String { "“\(inline(text))”" }

    static func count(_ value: Int, _ noun: String) -> String {
        "\(value) \(noun)\(value == 1 ? "" : "s")"
    }

    static func timestamp(_ date: Date) -> String {
        date.formatted(.iso8601)
    }

    static func name(of priority: TaskPriority) -> String {
        switch priority {
        case .high: "high"
        case .medium: "medium"
        case .low: "low"
        default: String(priority.rawValue)
        }
    }
}

extension ToolResult {
    /// Cuts the Markdown at the limit as a last guard; `get_map` already sizes
    /// its outline, so this only bites on a giant note or a long hit list.
    /// The structured copy is left whole, since cutting JSON would break it;
    /// those callers take their own `limit`.
    func limited(to limit: Int) -> ToolResult {
        guard text.count > limit else { return self }
        var copy = self
        copy.text = String(text.prefix(max(0, limit - 80))) + "\n\n… (cut at \(limit) characters)"
        return copy
    }
}

private extension String {
    func trimmingTrailingSpaces() -> String {
        var copy = self
        while copy.last == " " { copy.removeLast() }
        return copy
    }
}

/// Typed reads of a tool's `arguments`, with messages a model can act on.
struct Arguments {
    let values: [String: JSONValue]

    func string(_ key: String) throws(MapTools.InputError) -> String? {
        guard let value = values[key], value != .null else { return nil }
        guard let text = value.stringValue else { throw .init(message: "\(key) must be a string.") }
        return text
    }

    func optionalInt(_ key: String, in range: ClosedRange<Int>) throws(MapTools.InputError) -> Int? {
        guard let value = values[key], value != .null else { return nil }
        guard let number = value.intValue else { throw .init(message: "\(key) must be a whole number.") }
        return min(max(number, range.lowerBound), range.upperBound)
    }

    func int(_ key: String, default fallback: Int, in range: ClosedRange<Int>) throws(MapTools.InputError) -> Int {
        try optionalInt(key, in: range) ?? fallback
    }

    func bool(_ key: String, default fallback: Bool) throws(MapTools.InputError) -> Bool {
        guard let value = values[key], value != .null else { return fallback }
        guard let flag = value.boolValue else { throw .init(message: "\(key) must be true or false.") }
        return flag
    }

    func optionalMapID(_ key: String) throws(MapTools.InputError) -> MapID? {
        try uuid(key).map(MapID.init)
    }

    func mapID(_ key: String) throws(MapTools.InputError) -> MapID {
        guard let id = try optionalMapID(key) else { throw .init(message: "\(key) is required: a map ID from list_maps or search.") }
        return id
    }

    func nodeID(_ key: String) throws(MapTools.InputError) -> NodeID? {
        try uuid(key).map(NodeID.init)
    }

    func requiredNodeID(_ key: String) throws(MapTools.InputError) -> NodeID {
        guard let id = try nodeID(key) else { throw .init(message: "\(key) is required: a topic ID from get_map or search.") }
        return id
    }

    private func uuid(_ key: String) throws(MapTools.InputError) -> UUID? {
        guard let text = try string(key) else { return nil }
        guard let uuid = UUID(uuidString: text.trimmingCharacters(in: .whitespaces)) else {
            throw .init(message: "\(key) must be an ID as returned by an earlier call, like 8C6A1F2E-5B7D-4E3A-9F10-2D4C6B8A0E13.")
        }
        return uuid
    }
}

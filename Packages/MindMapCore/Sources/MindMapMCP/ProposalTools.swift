import Foundation
import MindMapDomain
import MindMapQuery

/// Topics an AI app proposes under one topic (docs/mcp.md, M5). Nothing in
/// the map changes: the app shows them as a suggestion labelled with the
/// client's name, and only the person's Accept turns them into a command.
public struct MCPProposal: Sendable, Hashable {
    public struct Topic: Sendable, Hashable {
        /// Temporary, p1, p2… in pre-order, parents first.
        public let id: String
        /// Another proposed topic; nil for a topic directly under `parentID`.
        public let parentID: String?
        public let title: String
        public let note: String?

        public init(id: String, parentID: String?, title: String, note: String?) {
            self.id = id
            self.parentID = parentID
            self.title = title
            self.note = note
        }
    }

    public let mapID: MapID
    /// The real topic the proposal hangs under.
    public let parentID: NodeID
    public let topics: [Topic]
    /// Who proposed it, for "Suggested by Claude Code".
    public let client: MCPClient

    public init(mapID: MapID, parentID: NodeID, topics: [Topic], client: MCPClient) {
        self.mapID = mapID
        self.parentID = parentID
        self.topics = topics
        self.client = client
    }
}

/// What the app did with a proposal, so the tool can tell the model whether
/// to wait or stop.
public enum MCPProposalOutcome: Sendable, Hashable {
    /// On the map now, waiting for review.
    case shown
    /// Kept until the map is open and its editor has no other suggestion.
    case waiting
    /// Allow Suggestions is off in Settings ▸ AI Apps.
    case notAllowed
    /// The map already has `MapTools.maximumWaitingProposals` waiting.
    case tooManyWaiting
}

/// Where proposals go: the app's open maps. The server has no write access
/// of its own (docs/mcp.md, Writing).
public protocol MCPProposalReceiver: Sendable {
    func receive(_ proposal: MCPProposal) async -> MCPProposalOutcome
}

extension MapTools {
    /// [Đề xuất] A proposal is for a person to read in one go: as many
    /// topics as a generated map, not a whole import.
    static let maximumProposedTopics = 20
    static let maximumTitleLength = 200
    static let maximumNoteLength = 2_000
    /// [Đề xuất] Proposals waiting on one map before the tool says to stop.
    public static let maximumWaitingProposals = 3

    // MARK: propose_topics

    func proposeTopics(_ arguments: Arguments, client: MCPClient) async throws -> ToolResult {
        guard let receiver = proposals else { throw CallError.unknownTool }
        let ref = TopicRef(mapID: try arguments.mapID("map_id"), nodeID: try arguments.requiredNodeID("parent_topic_id"))
        let topics = try Self.proposedTopics(arguments.values["topics"])
        guard let parent = try await queries.topic(ref) else {
            let isMapLive = try await queries.maps(matching: nil, limit: .max).contains { $0.mapID == ref.mapID }
            return .failure(isMapLive ? Self.topicNotFound : Self.mapNotFound)
        }

        let proposal = MCPProposal(mapID: ref.mapID, parentID: ref.nodeID, topics: topics, client: client)
        let count = Self.count(topics.count, "topic")
        let under = "under \(Self.quoted(parent.title)) in \(Self.quoted(parent.mapTitle))"
        let structured = { (status: String) -> JSONValue in
            ["status": .string(status), "map_id": .string(ref.mapID.description),
             "parent_topic_id": .string(ref.nodeID.description), "topic_count": .int(topics.count)]
        }
        // Never "added": the person decides in the app, and may change or
        // discard every topic first.
        switch await receiver.receive(proposal) {
        case .shown:
            return ToolResult(text: "Proposed \(count) \(under). Waiting for the person to review it in MindMap AI; nothing is added until they accept.",
                              structured: structured("waiting_for_review"))
        case .waiting:
            return ToolResult(text: "Proposed \(count) \(under). It will show when the person opens the map in MindMap AI; nothing is added until they accept.",
                              structured: structured("waiting_for_review"))
        case .notAllowed:
            return .failure("The person has not allowed AI apps to suggest topics. They can turn on Allow Suggestions in MindMap AI ▸ Settings ▸ AI Apps; until then only reading works.")
        case .tooManyWaiting:
            return .failure("This map already has \(Self.maximumWaitingProposals) proposals waiting for review. Wait for the person to accept or discard them before proposing more.")
        }
    }

    /// The `topics` tree in pre-order with temporary IDs p1, p2…: titles on
    /// one line, notes trimmed, every limit checked before anything reaches the app.
    static func proposedTopics(_ value: JSONValue?) throws(InputError) -> [MCPProposal.Topic] {
        guard let value, value != .null else {
            throw InputError(message: "topics is required: an array of objects with a title, and optionally a note and subtopics.")
        }
        var result: [MCPProposal.Topic] = []
        try collect(value, path: "topics", parentID: nil, into: &result)
        guard !result.isEmpty else { throw InputError(message: "topics must hold at least one topic.") }
        return result
    }

    private static func collect(_ value: JSONValue, path: String, parentID: String?, into result: inout [MCPProposal.Topic]) throws(InputError) {
        guard case let .array(items) = value else { throw InputError(message: "\(path) must be an array of topic objects.") }
        for (index, item) in items.enumerated() {
            let itemPath = "\(path)[\(index)]"
            guard case let .object(fields) = item else { throw InputError(message: "\(itemPath) must be an object with a title.") }
            if let unknown = fields.keys.sorted().first(where: { !["title", "note", "subtopics"].contains($0) }) {
                throw InputError(message: "\(itemPath) has an unknown field \(unknown); a topic takes title, note and subtopics only.")
            }
            guard let rawTitle = fields["title"]?.stringValue else { throw InputError(message: "\(itemPath).title must be a string.") }
            let title = inline(rawTitle).trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { throw InputError(message: "\(itemPath).title is empty.") }
            guard title.count <= maximumTitleLength else {
                throw InputError(message: "\(itemPath).title is over \(maximumTitleLength) characters; put the detail in note.")
            }
            var note: String?
            if let value = fields["note"], value != JSONValue.null {
                guard let text = value.stringValue else { throw InputError(message: "\(itemPath).note must be a string.") }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count <= maximumNoteLength else {
                    throw InputError(message: "\(itemPath).note is over \(maximumNoteLength) characters.")
                }
                note = trimmed.isEmpty ? nil : trimmed
            }
            guard result.count < maximumProposedTopics else {
                throw InputError(message: "Propose at most \(maximumProposedTopics) topics at a time, counting subtopics.")
            }
            let id = "p\(result.count + 1)"
            result.append(MCPProposal.Topic(id: id, parentID: parentID, title: title, note: note))
            if let subtopics = fields["subtopics"], subtopics != JSONValue.null {
                try collect(subtopics, path: "\(itemPath).subtopics", parentID: id, into: &result)
            }
        }
    }
}

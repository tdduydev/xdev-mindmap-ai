import Foundation
import MindMapDomain
import MindMapGraph

// Suggest Tags (MM-34): the model names up to three tags per topic, reusing
// the map's and the library's tag names where they fit. The suggestions are
// chips the person accepts one at a time or all at once; accepting is one
// `TagNodesCommand` batch with `origin = ai`, so it is one undo step.

/// One topic to tag, as the model sees it.
public struct TagSuggestionTopic: Hashable, Sendable {
    /// A short reference such as "t1", mapped back to the topic afterwards.
    public let reference: String
    public let nodeID: NodeID
    public let title: String
    /// The nearest ancestors' titles, parent last, for meaning.
    public let path: [String]
    /// Tags the topic already has, so the model does not repeat them.
    public let tags: [String]

    public init(reference: String, nodeID: NodeID, title: String, path: [String] = [], tags: [String] = []) {
        self.reference = reference
        self.nodeID = nodeID
        self.title = title
        self.path = path
        self.tags = tags
    }
}

public struct SuggestTagsRequest: Hashable, Sendable {
    public var mapTitle: String
    public var topics: [TagSuggestionTopic]
    /// The map's and the library's tag names, most used first, capped.
    public var availableTags: [String]
    public var language: AILanguage
    public var userLocaleIdentifier: String

    public init(
        mapTitle: String,
        topics: [TagSuggestionTopic],
        availableTags: [String],
        language: AILanguage,
        userLocaleIdentifier: String
    ) {
        self.mapTitle = mapTitle
        self.topics = Array(topics.prefix(AIProposalLimits.maximumTagSuggestionTopics))
        self.availableTags = availableTags
        self.language = language
        self.userLocaleIdentifier = userLocaleIdentifier
    }

    /// Tag names offered to the model. Thirty short names cost about as much
    /// as three topics, and are what lets it reuse the person's tags.
    public static let maximumAvailableTags = 30
    /// Titles are shortened to this many characters, as in `AIContextBuilder`.
    static let maximumTitleLength = 80

    /// The request for `nodeIDs`: several topics as they are, or one topic and
    /// the topics of its branch, in outline order, up to the request's cap.
    /// Nil when none of the topics exists.
    public static func make(
        for nodeIDs: [NodeID],
        in state: GraphState,
        language: AILanguage,
        userLocaleIdentifier: String
    ) -> SuggestTagsRequest? {
        let existing = nodeIDs.filter { state.node($0) != nil }
        guard let first = existing.first else { return nil }
        let ids = existing.count == 1 ? [first] + state.descendants(of: first) : existing
        let topics = ids.prefix(AIProposalLimits.maximumTagSuggestionTopics).enumerated().compactMap { index, id in
            state.node(id).map { node in
                TagSuggestionTopic(
                    reference: "t\(index + 1)",
                    nodeID: id,
                    title: shorten(node.title),
                    path: state.ancestors(of: id).prefix(2).reversed().compactMap { state.node($0).map { shorten($0.title) } },
                    tags: state.tags(of: id).map(\.name)
                )
            }
        }
        let counts = state.tagUseCounts()
        let available = state.tags.values
            .sorted { (-(counts[$0.id] ?? 0), $0.name) < (-(counts[$1.id] ?? 0), $1.name) }
            .map(\.name)
        var seen: Set<String> = []
        let names = available.filter { seen.insert(MindTag.key(for: $0)).inserted }
        return SuggestTagsRequest(
            mapTitle: shorten(state.map.title),
            topics: topics,
            availableTags: Array(names.prefix(maximumAvailableTags)),
            language: language,
            userLocaleIdentifier: userLocaleIdentifier
        )
    }

    private static func shorten(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return line.count <= maximumTitleLength ? line : String(line.prefix(maximumTitleLength - 1)) + "…"
    }

    public func topic(reference: String) -> TagSuggestionTopic? {
        topics.first { $0.reference == reference }
    }
}

/// Tag names suggested per topic, checked: known topics only, clean names, no
/// repeats, none the topic already has, at most three each.
public struct AITagSuggestions: Hashable, Sendable {
    public struct Entry: Hashable, Sendable {
        public let nodeID: NodeID
        public let names: [String]

        public init(nodeID: NodeID, names: [String]) {
            self.nodeID = nodeID
            self.names = names
        }
    }

    public var entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = entries
    }

    public var isEmpty: Bool { entries.allSatisfy(\.names.isEmpty) }

    /// What the model wrote, by topic reference, made safe to show. An unknown
    /// reference, a bad name or a repeat is dropped rather than failing the
    /// whole answer; nothing usable left is `ProposalError.empty`.
    public static func checked(_ answer: [(reference: String, names: [String])], for request: SuggestTagsRequest) throws -> AITagSuggestions {
        var entries: [NodeID: [String]] = [:]
        var order: [NodeID] = []
        for item in answer {
            guard let topic = request.topic(reference: item.reference.trimmingCharacters(in: .whitespaces)) else { continue }
            var keys = Set(topic.tags.map(MindTag.key(for:)))
            keys.formUnion((entries[topic.nodeID] ?? []).map(MindTag.key(for:)))
            var names = entries[topic.nodeID] ?? []
            for name in item.names.compactMap(MindTag.normalizedName) where names.count < AIProposalLimits.maximumTagsPerTopic {
                guard keys.insert(MindTag.key(for: name)).inserted else { continue }
                // An existing tag's own spelling, so accepting reuses it visibly.
                names.append(request.availableTags.first { MindTag.key(for: $0) == MindTag.key(for: name) } ?? name)
            }
            if entries[topic.nodeID] == nil { order.append(topic.nodeID) }
            entries[topic.nodeID] = names
        }
        let result = AITagSuggestions(entries: order.compactMap { id in
            entries[id].flatMap { $0.isEmpty ? nil : Entry(nodeID: id, names: $0) }
        })
        guard !result.isEmpty else { throw ProposalError.empty }
        return result
    }
}

/// Suggested tags while the person decides, kept apart from `GraphState` like
/// `SuggestionState`: nothing reaches the map, its history or the store
/// before Accept.
public struct TagSuggestionState: Hashable, Sendable {
    public struct Suggestion: Identifiable, Hashable, Sendable {
        /// Stable while the suggestions are shown, for selection and actions.
        public let id: String
        public let nodeID: NodeID
        public var name: String
    }

    public private(set) var suggestions: [Suggestion]

    public init(_ result: AITagSuggestions) {
        var counter = 0
        suggestions = result.entries.flatMap { entry in
            entry.names.map { name in
                counter += 1
                return Suggestion(id: "g\(counter)", nodeID: entry.nodeID, name: name)
            }
        }
    }

    public var isEmpty: Bool { suggestions.isEmpty }

    /// Topics with suggestions, in the order they were suggested.
    public var nodeIDs: [NodeID] {
        var seen: Set<NodeID> = []
        return suggestions.map(\.nodeID).filter { seen.insert($0).inserted }
    }

    public func suggestions(for nodeID: NodeID) -> [Suggestion] {
        suggestions.filter { $0.nodeID == nodeID }
    }

    public func suggestion(_ id: String) -> Suggestion? {
        suggestions.first { $0.id == id }
    }

    /// An edit before Accept. A name that cleans to nothing leaves it as it was.
    public mutating func rename(_ id: String, to name: String) {
        guard let name = MindTag.normalizedName(name), let index = suggestions.firstIndex(where: { $0.id == id }) else { return }
        suggestions[index].name = name
    }

    public mutating func remove(_ id: String) {
        suggestions.removeAll { $0.id == id }
    }

    /// Drops suggestions whose topic is gone (deleted or undone meanwhile), or
    /// which the topic now carries anyway.
    public mutating func prune(in state: GraphState) {
        suggestions.removeAll { suggestion in
            state.node(suggestion.nodeID) == nil
                || state.tags(of: suggestion.nodeID).contains { $0.key == MindTag.key(for: suggestion.name) }
        }
    }

    /// The accepted suggestions (all when nil) as one command: one
    /// `TagNodesCommand` per name, so a new name becomes one map tag shared by
    /// every topic it was suggested for. Dry-run on a copy, like topic proposals.
    public func accept(_ ids: Set<String>?, in engine: GraphEngine) throws -> BatchCommand {
        let accepted = suggestions.filter { ids?.contains($0.id) ?? true }
        if let ids, let unknown = ids.first(where: { id in !accepted.contains { $0.id == id } }) {
            throw ProposalError.unknownTopic(unknown)
        }
        var names: [String: (name: String, nodeIDs: [NodeID])] = [:]
        var order: [String] = []
        for suggestion in accepted where engine.state.node(suggestion.nodeID) != nil {
            let key = MindTag.key(for: suggestion.name)
            if names[key] == nil { order.append(key) }
            names[key, default: (suggestion.name, [])].nodeIDs.append(suggestion.nodeID)
        }
        guard !order.isEmpty else { throw ProposalError.anchorNotFound }
        let command = BatchCommand(order.compactMap { key in
            names[key].map { TagNodesCommand(nodeIDs: $0.nodeIDs, add: [.named($0.name)], origin: .ai) }
        })
        var probe = engine
        do {
            try probe.execute(command)
        } catch {
            throw ProposalError.rejectedByGraph
        }
        return command
    }

    public mutating func didAccept(_ ids: Set<String>?) {
        guard let ids else { return suggestions.removeAll() }
        suggestions.removeAll { ids.contains($0.id) }
    }
}

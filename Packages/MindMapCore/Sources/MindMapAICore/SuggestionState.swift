import Foundation
import MindMapDomain
import MindMapGraph

/// The AI suggestions waiting for a decision in one open map, kept apart from
/// `GraphState` so nothing the model writes reaches the map, its undo history
/// or the store until the person accepts it.
///
/// It follows a streamed proposal, keeps the person's edits (renamed and
/// removed topics), draws into a preview copy of the graph, and turns the
/// accepted part into one command.
public struct SuggestionState: Hashable, Sendable {
    public struct Topic: Hashable, Sendable, Identifiable {
        public let temporaryID: String
        /// Another suggestion this one hangs under; nil when it hangs under `anchorID`.
        public var parentTemporaryID: String?
        /// The real topic the suggestion, or its top suggested ancestor, attaches to.
        public var anchorID: NodeID
        public var title: String
        /// A node ID that stays the same while the answer streams in, so the
        /// canvas keeps the topic's place and measure from one snapshot to the next.
        public let previewID: NodeID

        public var id: String { temporaryID }
    }

    public let feature: AIFeature
    /// Where the top level of the proposal attaches.
    public let anchorID: NodeID
    /// Suggestions in pre-order, parents first.
    public private(set) var topics: [Topic] = []
    /// The title the model gave a generated map.
    public private(set) var suggestedMapTitle: String?
    /// False while the answer is still streaming; topics cannot be accepted yet.
    public private(set) var isComplete = false

    private var renamed: [String: String] = [:]
    private var removed: Set<String> = []
    private var previewIDs: [String: NodeID] = [:]

    public init(feature: AIFeature, anchorID: NodeID) {
        self.feature = feature
        self.anchorID = anchorID
    }

    public var isEmpty: Bool { topics.isEmpty }

    public func topic(_ temporaryID: String) -> Topic? {
        topics.first { $0.temporaryID == temporaryID }
    }

    public func topic(previewID: NodeID) -> Topic? {
        topics.first { $0.previewID == previewID }
    }

    // MARK: Following the stream

    /// Takes the latest snapshot of the answer. Topics the person removed stay
    /// removed and renamed ones keep the new title, so edits made after the
    /// answer completed survive a late snapshot.
    public mutating func update(with snapshot: ProposalSnapshot, makeNodeID: () -> NodeID = { NodeID() }) {
        let proposal = snapshot.proposal
        suggestedMapTitle = proposal.suggestedMapTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        isComplete = snapshot.isComplete

        // A partial snapshot can end in a topic whose parent has not been
        // written yet, and the model may list a subtopic before its parent or
        // repeat an ID. Only topics reached from the top level are kept, which
        // also leaves out loops; the rest may arrive in a later snapshot.
        var seen: Set<String> = []
        var candidates: [Topic] = []
        for raw in proposal.topics {
            let id = raw.temporaryID.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = raw.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !title.isEmpty, seen.insert(id).inserted else { continue }
            let parent = raw.parentTemporaryID?.trimmingCharacters(in: .whitespacesAndNewlines)
            let previewID = previewIDs[id] ?? makeNodeID()
            previewIDs[id] = previewID
            candidates.append(Topic(
                temporaryID: id,
                parentTemporaryID: parent?.isEmpty == false ? parent : nil,
                anchorID: anchorID,
                title: renamed[id] ?? title,
                previewID: previewID
            ))
        }
        // A removed topic takes its suggested subtopics with it.
        topics = Self.preorder(candidates).filter { topic in
            if removed.contains(topic.temporaryID) { return false }
            if let parent = topic.parentTemporaryID, removed.contains(parent) {
                removed.insert(topic.temporaryID)
                return false
            }
            return true
        }
    }

    // MARK: Editing

    /// Changes a suggestion's title before it is accepted. An empty title is
    /// ignored: a topic is accepted with a title or removed.
    public mutating func rename(_ temporaryID: String, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = topics.firstIndex(where: { $0.temporaryID == temporaryID }) else { return }
        topics[index].title = trimmed
        renamed[temporaryID] = trimmed
    }

    /// Discards one suggestion and the suggestions under it.
    public mutating func remove(_ temporaryID: String) {
        let gone = subtree(of: temporaryID)
        removed.formUnion(gone)
        topics.removeAll { gone.contains($0.temporaryID) }
    }

    // MARK: Preview

    /// The graph with every suggestion added under its anchor, for the canvas
    /// to lay out and draw. Suggestions whose anchor is gone (deleted, or an
    /// undone acceptance) are left out. The result is never saved.
    public func preview(in engine: GraphEngine) -> GraphState {
        let state = engine.state
        var commands: [any GraphCommand] = []
        var placed: Set<String> = []
        for topic in topics {
            let parent: NodeID
            if let parentTemporaryID = topic.parentTemporaryID {
                guard placed.contains(parentTemporaryID), let parentTopic = self.topic(parentTemporaryID) else { continue }
                parent = parentTopic.previewID
            } else {
                guard state.node(topic.anchorID) != nil else { continue }
                parent = topic.anchorID
            }
            placed.insert(topic.temporaryID)
            commands.append(AddNodeCommand(
                nodeID: topic.previewID,
                .child(of: parent, at: .last),
                title: topic.title,
                metadata: NodeMetadata(origin: .ai)
            ))
        }
        guard !commands.isEmpty else { return state }
        var copy = engine
        do {
            try copy.execute(BatchCommand(commands))
            return copy.state
        } catch {
            return state
        }
    }

    /// The suggestions a preview from `preview(in:)` holds, by preview ID.
    public func drawableTopics(in preview: GraphState) -> [NodeID: String] {
        topics.reduce(into: [:]) { result, topic in
            if preview.node(topic.previewID) != nil { result[topic.previewID] = topic.temporaryID }
        }
    }

    // MARK: Accepting

    /// The accepted suggestions as one command, and the node each became.
    /// `accepting` nil takes them all; a nested suggestion brings its suggested
    /// parents along. Throws `ProposalError`; the engine is never changed.
    public func accept(
        _ accepting: Set<String>? = nil,
        in engine: GraphEngine,
        makeNodeID: () -> NodeID = { NodeID() }
    ) throws -> AcceptedProposal {
        guard isComplete else { throw ProposalError.empty }
        let wanted = accepting ?? Set(topics.map(\.temporaryID))
        for id in wanted where topic(id) == nil { throw ProposalError.unknownTopic(id) }

        // Suggestions can sit under different real topics once part of a
        // generated tree has been accepted, so each anchor gets its own
        // proposal and the commands join into one batch.
        var nodeIDs: [String: NodeID] = [:]
        var commands: [any GraphCommand] = []
        let groups = Dictionary(grouping: topics, by: \.anchorID)
        for anchor in orderedAnchors() {
            guard let members = groups[anchor] else { continue }
            let memberIDs = Set(members.map(\.temporaryID))
            let chosen = wanted.intersection(memberIDs)
            guard !chosen.isEmpty else { continue }
            let proposal = AIProposal(
                feature: feature,
                anchor: .node(anchor),
                topics: members.map {
                    ProposedTopic(temporaryID: $0.temporaryID, parentTemporaryID: $0.parentTemporaryID, title: $0.title)
                }
            )
            let accepted = try ProposalTranslator.accept(proposal, topics: chosen, in: engine, makeNodeID: makeNodeID)
            commands.append(contentsOf: accepted.command.commands)
            nodeIDs.merge(accepted.nodeIDs) { first, _ in first }
        }
        guard !commands.isEmpty else { throw ProposalError.empty }

        let command = BatchCommand(commands)
        var copy = engine
        do {
            try copy.execute(command)
        } catch {
            throw ProposalError.rejectedByGraph
        }
        return AcceptedProposal(command: command, nodeIDs: nodeIDs)
    }

    /// Drops the suggestions that became real topics. Suggestions under an
    /// accepted one now hang under the real topic it became.
    public mutating func didAccept(_ nodeIDs: [String: NodeID]) {
        var remaining: [Topic] = []
        for var topic in topics where nodeIDs[topic.temporaryID] == nil {
            if let parent = topic.parentTemporaryID, let realID = nodeIDs[parent] {
                topic.parentTemporaryID = nil
                topic.anchorID = realID
            }
            remaining.append(topic)
        }
        // Children inherit the new anchor of their top suggested ancestor.
        var anchors: [String: NodeID] = [:]
        for index in remaining.indices {
            if let parent = remaining[index].parentTemporaryID, let anchor = anchors[parent] {
                remaining[index].anchorID = anchor
            }
            anchors[remaining[index].temporaryID] = remaining[index].anchorID
        }
        topics = remaining
    }

    // MARK: Helpers

    private func subtree(of temporaryID: String) -> Set<String> {
        var result: Set<String> = [temporaryID]
        // Pre-order puts every descendant after its parent.
        for topic in topics {
            if let parent = topic.parentTemporaryID, result.contains(parent) { result.insert(topic.temporaryID) }
        }
        return result
    }

    private func orderedAnchors() -> [NodeID] {
        var seen: Set<NodeID> = []
        return topics.compactMap { seen.insert($0.anchorID).inserted ? $0.anchorID : nil }
    }

    /// Parents before children, keeping the model's order among siblings.
    private static func preorder(_ topics: [Topic]) -> [Topic] {
        var children: [String?: [Topic]] = [:]
        for topic in topics { children[topic.parentTemporaryID, default: []].append(topic) }
        var ordered: [Topic] = []
        var stack = Array((children[String?.none] ?? []).reversed())
        while let next = stack.popLast() {
            ordered.append(next)
            stack.append(contentsOf: (children[next.temporaryID] ?? []).reversed())
        }
        return ordered
    }
}

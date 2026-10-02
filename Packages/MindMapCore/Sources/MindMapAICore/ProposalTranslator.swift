import Foundation
import MindMapDomain
import MindMapGraph

/// Why a proposal cannot become commands. The whole proposal is dropped and the
/// map is untouched.
public enum ProposalError: Error, Hashable, Sendable {
    case empty
    case emptyTemporaryID
    case duplicateTemporaryID(String)
    case emptyTitle(temporaryID: String)
    case unknownParent(temporaryID: String, parent: String)
    case cycle(temporaryID: String)
    /// The anchor topic is gone (deleted while the model was answering), or the
    /// map has no central topic.
    case anchorNotFound
    /// An accepted ID that is not in the proposal.
    case unknownTopic(String)
    /// The commands failed in a dry run against the current graph.
    case rejectedByGraph
}

/// The accepted part of a proposal as one command: running it is one undo step.
public struct AcceptedProposal: Sendable {
    public let command: BatchCommand
    /// The node each accepted temporary ID became, so the editor can select them.
    public let nodeIDs: [String: NodeID]
}

/// Turns AI output into graph commands, after checking it the same way every
/// time: temporary IDs unique, parents present, no loops, titles not empty,
/// and a dry run on a copy of the engine.
public enum ProposalTranslator {
    /// The topics with trimmed text, parents before children. Throws `ProposalError`.
    public static func validate(_ proposal: AIProposal) throws -> [ProposedTopic] {
        guard !proposal.topics.isEmpty else { throw ProposalError.empty }

        var topics: [ProposedTopic] = []
        var known: Set<String> = []
        for raw in proposal.topics {
            let id = raw.temporaryID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { throw ProposalError.emptyTemporaryID }
            guard known.insert(id).inserted else { throw ProposalError.duplicateTemporaryID(id) }
            let title = raw.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { throw ProposalError.emptyTitle(temporaryID: id) }
            // Models write "" or whitespace as often as null for "no parent".
            let parent = raw.parentTemporaryID?.trimmingCharacters(in: .whitespacesAndNewlines)
            let note = raw.note?.trimmingCharacters(in: .whitespacesAndNewlines)
            topics.append(ProposedTopic(
                temporaryID: id,
                parentTemporaryID: parent?.isEmpty == false ? parent : nil,
                title: title,
                note: note?.isEmpty == false ? note : nil
            ))
        }

        var childrenByParent: [String?: [ProposedTopic]] = [:]
        for topic in topics {
            if let parent = topic.parentTemporaryID, !known.contains(parent) {
                throw ProposalError.unknownParent(temporaryID: topic.temporaryID, parent: parent)
            }
            childrenByParent[topic.parentTemporaryID, default: []].append(topic)
        }

        // Pre-order from the top level, keeping the model's order among siblings.
        // A topic on a loop is never reached from the top level.
        var ordered: [ProposedTopic] = []
        var stack = Array((childrenByParent[String?.none] ?? []).reversed())
        while let next = stack.popLast() {
            ordered.append(next)
            stack.append(contentsOf: (childrenByParent[next.temporaryID] ?? []).reversed())
        }
        if ordered.count < topics.count {
            let reached = Set(ordered.map(\.temporaryID))
            let stranded = topics.first { !reached.contains($0.temporaryID) }
            throw ProposalError.cycle(temporaryID: stranded?.temporaryID ?? "")
        }
        return ordered
    }

    /// One command that adds the accepted topics, marked as written by AI.
    ///
    /// `accepting` nil takes every topic. Accepting a nested topic also takes
    /// its proposed parents, so the hierarchy the model suggested survives.
    /// Throws `ProposalError`, including `rejectedByGraph` when the commands fail
    /// on a copy of `engine`; the engine itself is never changed.
    public static func accept(
        _ proposal: AIProposal,
        topics accepting: Set<String>? = nil,
        in engine: GraphEngine,
        makeNodeID: () -> NodeID = { NodeID() }
    ) throws -> AcceptedProposal {
        let ordered = try validate(proposal)
        let anchorID = try resolve(proposal.anchor, in: engine.state)

        let byID = Dictionary(uniqueKeysWithValues: ordered.map { ($0.temporaryID, $0) })
        var accepted = Set(byID.keys)
        if let accepting {
            accepted = []
            for id in accepting {
                guard var topic = byID[id] else { throw ProposalError.unknownTopic(id) }
                accepted.insert(topic.temporaryID)
                while let parent = topic.parentTemporaryID, let parentTopic = byID[parent] {
                    accepted.insert(parent)
                    topic = parentTopic
                }
            }
        }
        guard !accepted.isEmpty else { throw ProposalError.empty }

        var nodeIDs: [String: NodeID] = [:]
        var commands: [any GraphCommand] = []
        for topic in ordered where accepted.contains(topic.temporaryID) {
            let nodeID = makeNodeID()
            let parentID = topic.parentTemporaryID.flatMap { nodeIDs[$0] } ?? anchorID
            nodeIDs[topic.temporaryID] = nodeID
            commands.append(AddNodeCommand(
                nodeID: nodeID,
                .child(of: parentID, at: .last),
                title: topic.title,
                note: topic.note,
                metadata: NodeMetadata(origin: .ai)
            ))
        }

        let command = BatchCommand(commands)
        try dryRun(command, on: engine)
        return AcceptedProposal(command: command, nodeIDs: nodeIDs)
    }

    /// Sets one of the suggested titles. Throws `ProposalError`.
    public static func accept(title: String, from rewrite: AIRewrite, in engine: GraphEngine) throws -> UpdateNodeCommand {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ProposalError.emptyTitle(temporaryID: "") }
        guard engine.state.node(rewrite.nodeID) != nil else { throw ProposalError.anchorNotFound }
        let command = UpdateNodeCommand(nodeID: rewrite.nodeID, .title(trimmed))
        try dryRun(command, on: engine)
        return command
    }

    /// Adds the summary to the end of the topic's note, keeping what the person
    /// wrote there. Throws `ProposalError`.
    public static func accept(_ summary: AISummary, in engine: GraphEngine) throws -> UpdateNodeCommand {
        let text = summary.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ProposalError.empty }
        guard let node = engine.state.node(summary.nodeID) else { throw ProposalError.anchorNotFound }
        let existing = node.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let note = existing.isEmpty ? text : existing + "\n\n" + text
        let command = UpdateNodeCommand(nodeID: summary.nodeID, .note(note))
        try dryRun(command, on: engine)
        return command
    }

    private static func resolve(_ anchor: ProposalAnchor, in state: GraphState) throws -> NodeID {
        switch anchor {
        case .root:
            guard let rootID = state.map.rootNodeID, state.node(rootID) != nil else { throw ProposalError.anchorNotFound }
            return rootID
        case .node(let id):
            guard state.node(id) != nil else { throw ProposalError.anchorNotFound }
            return id
        }
    }

    /// The engine is a value, so a copy runs the full validation without
    /// touching the editor's graph or its undo history.
    private static func dryRun(_ command: any GraphCommand, on engine: GraphEngine) throws {
        var copy = engine
        do {
            try copy.execute(command)
        } catch {
            throw ProposalError.rejectedByGraph
        }
    }
}

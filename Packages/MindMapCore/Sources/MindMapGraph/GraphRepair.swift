import Foundation
import MindMapDomain

public struct GraphRepairResult: Sendable {
    public let state: GraphState
    /// What was wrong before the repair. Empty when nothing needed fixing.
    public let issues: Set<GraphIssue>
    /// The records the repair changed; save them so it does not run again.
    public let changes: GraphChangeSet
}

/// Turns any stored graph into a valid one without losing a node.
///
/// Sync merges per record, so concurrent edits on two devices can leave a
/// branch without its parent or two nodes under each other. Instead of
/// dropping that content, the repair hangs it under the root where the user
/// can see it. Only edges whose endpoints are gone are removed.
///
/// Choices are deterministic (timestamps, then IDs), so two devices repairing
/// the same data independently produce the same result.
public enum GraphRepair {
    public static func repair(_ state: GraphState, now: Date) throws -> GraphRepairResult {
        let issues = GraphValidator.validate(state)
        guard !issues.isEmpty else {
            return GraphRepairResult(state: state, issues: [], changes: GraphChangeSet())
        }

        var transaction = GraphTransaction(state: state, now: now)
        try removeBrokenEdges(in: &transaction)
        try ensureRoot(in: &transaction)

        if let rootID = transaction.state.map.rootNodeID {
            let remaining = GraphValidator.validate(transaction.state)
            for id in branchesToReattach(for: remaining, in: transaction.state) {
                let sortOrder = try transaction.sortOrder(for: .last, under: rootID, excluding: id)
                try transaction.updateNode(id) { node in
                    node.parentID = rootID
                    node.sortOrder = sortOrder
                }
            }
        }

        return GraphRepairResult(state: transaction.state, issues: issues, changes: transaction.changes)
    }

    private static func removeBrokenEdges(in transaction: inout GraphTransaction) throws {
        let state = transaction.state
        let broken = state.edges.values.filter { edge in
            state.node(edge.sourceNodeID) == nil
                || state.node(edge.targetNodeID) == nil
                || edge.sourceNodeID == edge.targetNodeID
        }
        for edge in broken {
            try transaction.removeEdge(edge.id)
        }
    }

    private static func ensureRoot(in transaction: inout GraphTransaction) throws {
        if transaction.state.root == nil {
            guard let newRootID = rootCandidate(in: transaction.state) else {
                transaction.updateMap { $0.rootNodeID = nil }
                return
            }
            transaction.updateMap { $0.rootNodeID = newRootID }
        }
        if let rootID = transaction.state.map.rootNodeID {
            try transaction.updateNode(rootID) { $0.parentID = nil }
        }
    }

    /// Prefers a node that already has no parent, then the top of a branch whose
    /// parent is gone, then any node; the oldest wins.
    private static func rootCandidate(in state: GraphState) -> NodeID? {
        let all = state.nodes.values.sorted(by: oldestFirst)
        return all.first { $0.parentID == nil }?.id
            ?? all.first { $0.parentID.map { state.node($0) == nil } ?? false }?.id
            ?? all.first?.id
    }

    /// Detached branch tops, plus one node cut from each loop. The cut is the
    /// most recently edited node in the loop, which is most likely the move that
    /// created it.
    private static func branchesToReattach(for issues: Set<GraphIssue>, in state: GraphState) -> [NodeID] {
        var targets: [MindNode] = []
        var loopMembers: Set<NodeID> = []
        for issue in issues {
            switch issue {
            case .detachedBranch(let id):
                if let node = state.node(id) { targets.append(node) }
            case .cycle(let id):
                loopMembers.insert(id)
            default:
                break
            }
        }

        var seen: Set<NodeID> = []
        for id in loopMembers.sorted() where !seen.contains(id) {
            let loop = loop(containing: id, in: state)
            seen.formUnion(loop.map(\.id))
            if let cut = loop.max(by: { ($0.updatedAt, $0.id) < ($1.updatedAt, $1.id) }) {
                targets.append(cut)
            }
        }
        return targets.sorted(by: oldestFirst).map(\.id)
    }

    private static func loop(containing id: NodeID, in state: GraphState) -> [MindNode] {
        var members: [MindNode] = []
        var visited: Set<NodeID> = []
        var current: NodeID? = id
        while let next = current, visited.insert(next).inserted, let node = state.node(next) {
            members.append(node)
            current = node.parentID
        }
        return members
    }

    private static func oldestFirst(_ lhs: MindNode, _ rhs: MindNode) -> Bool {
        (lhs.createdAt, lhs.id) < (rhs.createdAt, rhs.id)
    }
}

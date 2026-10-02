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
/// Organization records are repaired after the tree: tag links whose topic is
/// gone are deleted, links waiting for a tag that never arrived are deleted
/// after `orphanedTagLinkLifetime`, duplicate map tags merge into the oldest,
/// duplicate links keep the oldest, and boundaries shrink back to a valid run.
///
/// Choices are deterministic (timestamps, then IDs), so two devices repairing
/// the same data independently produce the same result.
public enum GraphRepair {
    /// How long a tag link may wait for its tag to sync before it is deleted:
    /// long enough for a device that was offline for weeks [Đề xuất].
    public static let orphanedTagLinkLifetime: TimeInterval = 30 * 24 * 60 * 60

    public static func repair(_ state: GraphState, now: Date) throws -> GraphRepairResult {
        let issues = GraphValidator.validate(state)
        let expiredLinks = expiredTagLinks(in: state, now: now)
        guard !issues.isEmpty || !expiredLinks.isEmpty else {
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

        for id in expiredLinks where transaction.state.nodeTags[id] != nil {
            try transaction.removeNodeTag(id)
        }
        try removeDanglingTagLinks(in: &transaction)
        try mergeDuplicateTags(in: &transaction)
        try removeDuplicateTagLinks(in: &transaction)
        try repairGroups(in: &transaction)

        return GraphRepairResult(state: transaction.state, issues: issues, changes: transaction.changes)
    }

    // MARK: Organization

    private static func expiredTagLinks(in state: GraphState, now: Date) -> [NodeTagID] {
        state.nodeTags.values
            .filter { state.tags[$0.tagID] == nil && now.timeIntervalSince($0.createdAt) > orphanedTagLinkLifetime }
            .map(\.id)
            .sorted()
    }

    private static func removeDanglingTagLinks(in transaction: inout GraphTransaction) throws {
        let state = transaction.state
        for link in state.nodeTags.values.sorted(by: GraphValidator.oldestFirst) where state.node(link.nodeID) == nil {
            try transaction.removeNodeTag(link.id)
        }
    }

    /// Map tags with one key fold into the oldest: their links move to it and
    /// the duplicates go. Shared tags belong to the library's repair.
    private static func mergeDuplicateTags(in transaction: inout GraphTransaction) throws {
        let mapID = transaction.state.map.id
        let byKey = Dictionary(grouping: transaction.state.tags.values.filter { $0.mapID == mapID }, by: \.key)
        for key in byKey.keys.sorted() {
            guard let tags = byKey[key]?.sorted(by: GraphValidator.oldestFirst), let survivor = tags.first else { continue }
            for duplicate in tags.dropFirst() {
                try transaction.moveTagLinks(from: duplicate.id, to: survivor.id)
                try transaction.removeTag(duplicate.id)
            }
        }
    }

    private static func removeDuplicateTagLinks(in transaction: inout GraphTransaction) throws {
        var seen: Set<GraphValidator.TagLinkKey> = []
        for link in transaction.state.nodeTags.values.sorted(by: GraphValidator.oldestFirst)
        where !seen.insert(GraphValidator.TagLinkKey(nodeID: link.nodeID, tagID: link.tagID)).inserted {
            try transaction.removeNodeTag(link.id)
        }
    }

    /// Shrinks a boundary to the ends still under its parent, swaps ends that
    /// are out of order, and deletes a boundary with no member left. Crossing
    /// boundaries from two devices are drawn as they are and left alone.
    private static func repairGroups(in transaction: inout GraphTransaction) throws {
        let state = transaction.state
        let broken = state.groups.values
            .filter { $0.kind == .boundary && state.members(of: $0) == nil }
            .sorted { $0.id < $1.id }
        for group in broken {
            guard let parentID = group.parentNodeID, state.node(parentID) != nil else {
                try transaction.removeGroup(group.id)
                continue
            }
            let siblings = state.childIDs(of: parentID)
            let ends = [group.firstNodeID, group.lastNodeID].compactMap { $0.flatMap { siblings.firstIndex(of: $0) } }
            guard let low = ends.min(), let high = ends.max() else {
                try transaction.removeGroup(group.id)
                continue
            }
            try transaction.updateGroup(group.id) { group in
                group.firstNodeID = siblings[low]
                group.lastNodeID = siblings[high]
            }
        }
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

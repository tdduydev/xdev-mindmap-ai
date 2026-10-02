import Foundation
import MindMapDomain

/// Copies a node and its whole branch right after the original, under the same
/// parent. Copies get new IDs and keep titles, notes, collapsed state, type and
/// metadata. Cross-links with both ends inside the branch are copied too; links
/// that leave the branch stay with the original only, since a copy pointing at
/// the same outside topic is rarely what the user meant.
public struct DuplicateBranchCommand: GraphCommand {
    public let nodeID: NodeID
    /// The ID of the copied top node, chosen up front so the caller can select it.
    public let copyID: NodeID

    public init(nodeID: NodeID, copyID: NodeID = NodeID()) {
        self.nodeID = nodeID
        self.copyID = copyID
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        let state = transaction.state
        guard let original = state.node(nodeID) else { throw GraphError.nodeNotFound(nodeID) }
        guard let parentID = original.parentID else { throw GraphError.rootHasNoSiblings }

        var newIDs: [NodeID: NodeID] = [nodeID: copyID]
        let topOrder = try transaction.sortOrder(for: .after(nodeID), under: parentID)
        try transaction.insertNode(copy(of: original, id: copyID, parentID: parentID, sortOrder: topOrder, now: transaction.now))

        // Pre-order, so every parent is in place before its children. Children
        // are renumbered 0, 1, 2… because copies share one creation time, and
        // equal sort keys from sync would otherwise reorder by the new random IDs.
        var stack = [nodeID]
        while let sourceParent = stack.popLast() {
            guard let copiedParent = newIDs[sourceParent] else { continue }
            for (index, child) in state.children(of: sourceParent).enumerated() {
                let id = NodeID()
                newIDs[child.id] = id
                try transaction.insertNode(copy(of: child, id: id, parentID: copiedParent, sortOrder: Double(index), now: transaction.now))
                stack.append(child.id)
            }
        }

        let internalEdges = state.edges.values
            .filter { newIDs[$0.sourceNodeID] != nil && newIDs[$0.targetNodeID] != nil }
            .sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
        for edge in internalEdges {
            guard let source = newIDs[edge.sourceNodeID], let target = newIDs[edge.targetNodeID] else { continue }
            try transaction.insertEdge(MindEdge(
                mapID: edge.mapID,
                sourceNodeID: source,
                targetNodeID: target,
                edgeType: edge.edgeType,
                label: edge.label,
                createdAt: transaction.now
            ))
        }
    }

    private func copy(of node: MindNode, id: NodeID, parentID: NodeID, sortOrder: Double, now: Date) -> MindNode {
        MindNode(
            id: id,
            mapID: node.mapID,
            parentID: parentID,
            title: node.title,
            note: node.note,
            sortOrder: sortOrder,
            isCollapsed: node.isCollapsed,
            nodeType: node.nodeType,
            metadata: node.metadata,
            createdAt: now
        )
    }
}

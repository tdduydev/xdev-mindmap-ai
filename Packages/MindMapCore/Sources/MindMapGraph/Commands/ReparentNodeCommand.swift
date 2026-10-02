import Foundation
import MindMapDomain

/// Moves a node, with its branch, under a parent at a position. Covers
/// reparenting, moving and reordering within the same parent.
public struct ReparentNodeCommand: GraphCommand {
    public let nodeID: NodeID
    public let newParentID: NodeID
    public let placement: ChildPlacement

    public init(nodeID: NodeID, newParentID: NodeID, placement: ChildPlacement = .last) {
        self.nodeID = nodeID
        self.newParentID = newParentID
        self.placement = placement
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        let state = transaction.state
        guard state.node(nodeID) != nil else { throw GraphError.nodeNotFound(nodeID) }
        guard state.node(newParentID) != nil else { throw GraphError.nodeNotFound(newParentID) }
        guard nodeID != state.map.rootNodeID else { throw GraphError.cannotMoveRoot }
        guard nodeID != newParentID, !state.isAncestor(nodeID, of: newParentID) else {
            throw GraphError.wouldCreateCycle(node: nodeID, newParent: newParentID)
        }

        let sortOrder = try transaction.sortOrder(for: placement, under: newParentID, excluding: nodeID)
        try transaction.updateNode(nodeID) { node in
            node.parentID = newParentID
            node.sortOrder = sortOrder
        }
    }
}

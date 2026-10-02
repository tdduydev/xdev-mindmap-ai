import Foundation
import MindMapDomain

/// Moves a topic, with its branch, up one level: it becomes the sibling right
/// after its parent. Later siblings stay where they are, so only the moved
/// topic's record changes.
public struct PromoteNodeCommand: GraphCommand {
    public let nodeID: NodeID

    public init(nodeID: NodeID) {
        self.nodeID = nodeID
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        let state = transaction.state
        guard let node = state.node(nodeID) else { throw GraphError.nodeNotFound(nodeID) }
        guard let parentID = node.parentID else { throw GraphError.cannotMoveRoot }
        guard let grandparentID = state.node(parentID)?.parentID else { throw GraphError.alreadyTopLevel(nodeID) }

        let sortOrder = try transaction.sortOrder(for: .after(parentID), under: grandparentID, excluding: nodeID)
        try transaction.updateNode(nodeID) { node in
            node.parentID = grandparentID
            node.sortOrder = sortOrder
        }
    }

    /// Whether the command would apply, for enabling menu items.
    public static func canPromote(_ id: NodeID, in state: GraphState) -> Bool {
        guard let parentID = state.node(id)?.parentID else { return false }
        return state.node(parentID)?.parentID != nil
    }
}

/// Moves a topic, with its branch, down one level: it becomes the last child of
/// the sibling right before it. That sibling opens if it was collapsed, or the
/// topic would disappear from view.
public struct DemoteNodeCommand: GraphCommand {
    public let nodeID: NodeID

    public init(nodeID: NodeID) {
        self.nodeID = nodeID
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        let state = transaction.state
        guard state.node(nodeID) != nil else { throw GraphError.nodeNotFound(nodeID) }
        guard nodeID != state.map.rootNodeID else { throw GraphError.cannotMoveRoot }
        guard let newParentID = Self.previousSibling(of: nodeID, in: state) else {
            throw GraphError.noPreviousSibling(nodeID)
        }

        let sortOrder = try transaction.sortOrder(for: .last, under: newParentID, excluding: nodeID)
        try transaction.updateNode(nodeID) { node in
            node.parentID = newParentID
            node.sortOrder = sortOrder
        }
        try transaction.updateNode(newParentID) { $0.isCollapsed = false }
    }

    /// Whether the command would apply, for enabling menu items.
    public static func canDemote(_ id: NodeID, in state: GraphState) -> Bool {
        previousSibling(of: id, in: state) != nil
    }

    private static func previousSibling(of id: NodeID, in state: GraphState) -> NodeID? {
        guard let parentID = state.node(id)?.parentID else { return nil }
        let siblings = state.childIDs(of: parentID)
        guard let index = siblings.firstIndex(of: id), index > 0 else { return nil }
        return siblings[index - 1]
    }
}

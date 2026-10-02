import Foundation
import MindMapDomain

/// Where a new node goes.
public enum NodeInsertion: Hashable, Sendable {
    /// The map's root. Fails if the map already has one.
    case root
    case child(of: NodeID, at: ChildPlacement = .last)
    /// Right after a node, under the same parent. The root has no siblings.
    case sibling(after: NodeID)
}

/// Creates one node.
///
/// The caller picks `nodeID` up front, so it can select and focus the new node
/// straight away without searching for it.
public struct AddNodeCommand: GraphCommand {
    public let nodeID: NodeID
    public let insertion: NodeInsertion
    public let title: String
    public let note: String?
    public let nodeType: NodeType
    public let metadata: NodeMetadata

    public init(
        nodeID: NodeID = NodeID(),
        _ insertion: NodeInsertion,
        title: String,
        note: String? = nil,
        nodeType: NodeType = .topic,
        metadata: NodeMetadata = NodeMetadata()
    ) {
        self.nodeID = nodeID
        self.insertion = insertion
        self.title = title
        self.note = note
        self.nodeType = nodeType
        self.metadata = metadata
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        let parentID: NodeID?
        let sortOrder: Double

        switch insertion {
        case .root:
            guard transaction.state.map.rootNodeID == nil else { throw GraphError.rootAlreadyExists }
            parentID = nil
            sortOrder = 0
        case .child(let parent, let placement):
            guard transaction.state.node(parent) != nil else { throw GraphError.nodeNotFound(parent) }
            parentID = parent
            sortOrder = try transaction.sortOrder(for: placement, under: parent)
        case .sibling(let anchor):
            guard let anchorNode = transaction.state.node(anchor) else { throw GraphError.nodeNotFound(anchor) }
            guard let parent = anchorNode.parentID else { throw GraphError.rootHasNoSiblings }
            parentID = parent
            sortOrder = try transaction.sortOrder(for: .after(anchor), under: parent)
        }

        if let parentID {
            // A new child inside a collapsed branch would be invisible, so open the
            // branch in the same undo step.
            try transaction.updateNode(parentID) { $0.isCollapsed = false }
        }

        let node = MindNode(
            id: nodeID,
            mapID: transaction.state.map.id,
            parentID: parentID,
            title: title,
            note: note,
            sortOrder: sortOrder,
            nodeType: nodeType,
            metadata: metadata,
            createdAt: transaction.now
        )
        try transaction.insertNode(node)

        if parentID == nil {
            transaction.updateMap { $0.rootNodeID = nodeID }
        }
    }
}

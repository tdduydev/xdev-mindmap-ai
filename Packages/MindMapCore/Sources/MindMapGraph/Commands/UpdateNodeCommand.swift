import Foundation
import MindMapDomain

/// One attribute to set on a node. Hierarchy is not here: moving a node is
/// `ReparentNodeCommand`, which checks for cycles.
public enum NodeAttributeChange: Hashable, Sendable {
    case title(String)
    case note(String?)
    case isCollapsed(Bool)
    case nodeType(NodeType)
    case metadata(NodeMetadata)

    func apply(to node: inout MindNode) {
        switch self {
        case .title(let title): node.title = title
        case .note(let note): node.note = note
        case .isCollapsed(let isCollapsed): node.isCollapsed = isCollapsed
        case .nodeType(let nodeType): node.nodeType = nodeType
        case .metadata(let metadata): node.metadata = metadata
        }
    }
}

/// Sets attributes on one node. Setting values the node already has is a no-op
/// and adds nothing to undo history.
public struct UpdateNodeCommand: GraphCommand {
    public let nodeID: NodeID
    public let changes: [NodeAttributeChange]

    public init(nodeID: NodeID, changes: [NodeAttributeChange]) {
        self.nodeID = nodeID
        self.changes = changes
    }

    public init(nodeID: NodeID, _ change: NodeAttributeChange) {
        self.init(nodeID: nodeID, changes: [change])
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        try transaction.updateNode(nodeID) { node in
            for change in changes {
                change.apply(to: &node)
            }
        }
    }
}

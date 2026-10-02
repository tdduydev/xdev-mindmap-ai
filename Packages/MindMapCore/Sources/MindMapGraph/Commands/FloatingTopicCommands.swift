import Foundation
import MindMapDomain

// Floating topics (FR-ORG-27, ADR 0010): a topic with no parent that is not
// the central topic and has a stored position. Attaching one to a topic goes
// through `ReparentNodeCommand`, whose update clears the position; the editor
// names that step "Move Topic", like any other move.

/// Creates a floating topic centred at `position`. The editor names the step
/// "Add Floating Topic".
///
/// The map must already have its central topic: a floating topic is never the
/// first topic of a map, so a map keeps exactly one central topic.
public struct AddFloatingTopicCommand: GraphCommand {
    /// Chosen up front so the caller can select and focus the new topic.
    public let nodeID: NodeID
    public let title: String
    public let position: TopicPosition
    public let metadata: NodeMetadata

    public init(
        nodeID: NodeID = NodeID(),
        title: String,
        position: TopicPosition,
        metadata: NodeMetadata = NodeMetadata()
    ) {
        self.nodeID = nodeID
        self.title = title
        self.position = position
        self.metadata = metadata
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        guard let rootID = transaction.state.map.rootNodeID, transaction.state.node(rootID) != nil else {
            throw GraphError.noCentralTopic
        }
        // Floating topics are ordered by creation time, not `sortOrder`, so any
        // value works; 0 keeps the record the same on every device.
        try transaction.insertNode(MindNode(
            id: nodeID,
            mapID: transaction.state.map.id,
            parentID: nil,
            title: title,
            sortOrder: 0,
            metadata: metadata,
            createdAt: transaction.now,
            position: position
        ))
    }
}

/// Moves a floating topic, with its branch, to a new position. The editor
/// names the step "Move Topic".
public struct MoveFloatingTopicCommand: GraphCommand {
    public let nodeID: NodeID
    public let position: TopicPosition

    public init(nodeID: NodeID, to position: TopicPosition) {
        self.nodeID = nodeID
        self.position = position
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        guard let node = transaction.state.node(nodeID) else { throw GraphError.nodeNotFound(nodeID) }
        guard node.isFloating(rootID: transaction.state.map.rootNodeID) else { throw GraphError.notFloating(nodeID) }
        try transaction.updateNode(nodeID) { $0.position = position }
    }
}

/// Takes a branch out of the tree and makes its top a floating topic at
/// `position`. The editor names the step "Detach Topic".
///
/// Leaving its parent also takes the topic out of the boundaries and
/// summaries it ended there (`GraphTransaction.updateNode`), so undo puts
/// them back with it.
public struct DetachBranchCommand: GraphCommand {
    public let nodeID: NodeID
    public let position: TopicPosition

    public init(nodeID: NodeID, position: TopicPosition) {
        self.nodeID = nodeID
        self.position = position
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        guard let node = transaction.state.node(nodeID) else { throw GraphError.nodeNotFound(nodeID) }
        guard nodeID != transaction.state.map.rootNodeID else { throw GraphError.cannotMoveRoot }
        // Already floating: that is a move, and the caller should say so.
        guard node.parentID != nil else { throw GraphError.notInTree(nodeID) }
        try transaction.updateNode(nodeID) { node in
            node.parentID = nil
            node.position = position
        }
    }
}

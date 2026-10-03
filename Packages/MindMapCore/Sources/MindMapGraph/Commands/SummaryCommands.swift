import Foundation
import MindMapDomain

/// Brackets a run of adjacent siblings and adds the summary topic beyond the
/// bracket (FR-ORG-29): "Add Summary".
///
/// The summary topic is an ordinary child of the run's parent, added last, so
/// it stays in the tree (ADR 0004); the group naming it is what keeps it out of
/// the parent's column. Refuses what `AddGroupCommand` refuses, checked
/// against the other summaries under the parent.
public struct AddSummaryCommand: GraphCommand {
    /// Both chosen up front so the caller can select the bracket or start
    /// typing in the summary topic.
    public let groupID: GroupID
    public let nodeID: NodeID
    public let firstNodeID: NodeID
    public let lastNodeID: NodeID
    public let title: String

    public init(
        groupID: GroupID = GroupID(),
        nodeID: NodeID = NodeID(),
        from firstNodeID: NodeID,
        to lastNodeID: NodeID? = nil,
        title: String = ""
    ) {
        self.groupID = groupID
        self.nodeID = nodeID
        self.firstNodeID = firstNodeID
        self.lastNodeID = lastNodeID ?? firstNodeID
        self.title = title
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        let run = try AddGroupCommand.validRun(from: firstNodeID, to: lastNodeID, kind: .summary, in: transaction.state)
        try AddNodeCommand(nodeID: nodeID, .child(of: run.parentID, at: .last), title: title).execute(in: &transaction)
        try transaction.insertGroup(MindGroup(
            id: groupID,
            mapID: transaction.state.map.id,
            kind: .summary,
            parentNodeID: run.parentID,
            firstNodeID: run.firstID,
            lastNodeID: run.lastID,
            createdAt: transaction.now,
            summaryNodeID: nodeID
        ))
    }
}

/// Removes a summary's bracket and its summary topic with that topic's
/// branch, in one step: "Remove Summary". The bracketed topics stay.
public struct RemoveSummaryCommand: GraphCommand {
    public let groupID: GroupID

    public init(groupID: GroupID) {
        self.groupID = groupID
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        guard let group = transaction.state.group(groupID), group.kind == .summary else {
            throw GraphError.groupNotFound(groupID)
        }
        // Deleting the topic takes the groups naming it, this one included.
        if let topicID = group.summaryNodeID, transaction.state.node(topicID) != nil {
            try DeleteNodeCommand(nodeID: topicID).execute(in: &transaction)
        }
        if transaction.state.group(groupID) != nil {
            try transaction.removeGroup(groupID)
        }
    }
}

import Foundation
import MindMapDomain

/// Draws a cross-link between two topics. Hierarchy never goes through here:
/// it is `MindNode.parentID` only (ADR 0004).
public struct ConnectNodesCommand: GraphCommand {
    /// Chosen up front so the caller can select or label the new link.
    public let edgeID: EdgeID
    public let sourceID: NodeID
    public let targetID: NodeID
    public let edgeType: EdgeType
    public let label: String?

    public init(
        edgeID: EdgeID = EdgeID(),
        from sourceID: NodeID,
        to targetID: NodeID,
        type edgeType: EdgeType = .relationship,
        label: String? = nil
    ) {
        self.edgeID = edgeID
        self.sourceID = sourceID
        self.targetID = targetID
        self.edgeType = edgeType
        self.label = label
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        let state = transaction.state
        guard state.node(sourceID) != nil else { throw GraphError.nodeNotFound(sourceID) }
        guard state.node(targetID) != nil else { throw GraphError.nodeNotFound(targetID) }
        guard sourceID != targetID else { throw GraphError.cannotLinkToItself(sourceID) }
        // A second identical link would draw on top of the first and look like one.
        if let existing = state.edges(touching: sourceID).first(where: {
            $0.sourceNodeID == sourceID && $0.targetNodeID == targetID && $0.edgeType == edgeType
        }) {
            throw GraphError.edgeAlreadyExists(existing.id)
        }

        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        try transaction.insertEdge(MindEdge(
            id: edgeID,
            mapID: state.map.id,
            sourceNodeID: sourceID,
            targetNodeID: targetID,
            edgeType: edgeType,
            label: trimmed?.isEmpty == false ? trimmed : nil,
            createdAt: transaction.now
        ))
    }
}

/// Deletes one cross-link. The topics it joined stay.
public struct RemoveEdgeCommand: GraphCommand {
    public let edgeID: EdgeID

    public init(edgeID: EdgeID) {
        self.edgeID = edgeID
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        try transaction.removeEdge(edgeID)
    }
}

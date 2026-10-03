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

/// Edits a cross-link's label and look in one undo step. Setting a style
/// field to nil brings back the look V1 derives from `edgeType`.
public struct UpdateEdgeCommand: GraphCommand {
    public let edgeID: EdgeID
    public let label: FieldChange<String?>
    public let lineStyle: FieldChange<EdgeLineStyle?>
    public let arrowHeads: FieldChange<EdgeArrowHeads?>
    public let color: FieldChange<TopicColor?>

    public init(
        edgeID: EdgeID,
        label: FieldChange<String?> = .keep,
        lineStyle: FieldChange<EdgeLineStyle?> = .keep,
        arrowHeads: FieldChange<EdgeArrowHeads?> = .keep,
        color: FieldChange<TopicColor?> = .keep
    ) {
        self.edgeID = edgeID
        self.label = label
        self.lineStyle = lineStyle
        self.arrowHeads = arrowHeads
        self.color = color
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        // Whitespace alone would draw an empty capsule on the canvas.
        let label = label.map { text -> String? in
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }
        try transaction.updateEdge(edgeID) { edge in
            label.apply(to: &edge.label)
            lineStyle.apply(to: &edge.lineStyle)
            arrowHeads.apply(to: &edge.arrowHeads)
            color.apply(to: &edge.color)
        }
    }
}

/// Swaps a cross-link's ends, so an arrow at the end points the other way.
public struct ReverseEdgeCommand: GraphCommand {
    public let edgeID: EdgeID

    public init(edgeID: EdgeID) {
        self.edgeID = edgeID
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        guard let edge = transaction.state.edges[edgeID] else { throw GraphError.edgeNotFound(edgeID) }
        // The reversed link may already exist; two on top of each other read as one.
        if let existing = transaction.state.edges(touching: edge.targetNodeID).first(where: {
            $0.id != edgeID && $0.sourceNodeID == edge.targetNodeID
                && $0.targetNodeID == edge.sourceNodeID && $0.edgeType == edge.edgeType
        }) {
            throw GraphError.edgeAlreadyExists(existing.id)
        }
        try transaction.updateEdge(edgeID) { edge in
            swap(&edge.sourceNodeID, &edge.targetNodeID)
        }
    }
}

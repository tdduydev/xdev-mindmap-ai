import Foundation

/// A cross-link between two nodes.
///
/// Parent–child structure is deliberately not an edge: it lives only in
/// `MindNode.parentID`. Storing it twice would give hierarchy two sources of
/// truth that can disagree after devices sync.
public struct MindEdge: Identifiable, Hashable, Sendable, Codable {
    public let id: EdgeID
    public let mapID: MapID
    public var sourceNodeID: NodeID
    public var targetNodeID: NodeID
    public var edgeType: EdgeType
    public var label: String?
    /// Nil keeps the look V1 derives from `edgeType`.
    public var lineStyle: EdgeLineStyle?
    /// Nil keeps the look V1 derives from `edgeType`.
    public var arrowHeads: EdgeArrowHeads?
    /// Nil is the cross-link colour.
    public var color: TopicColor?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: EdgeID = EdgeID(),
        mapID: MapID,
        sourceNodeID: NodeID,
        targetNodeID: NodeID,
        edgeType: EdgeType = .relationship,
        label: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date? = nil,
        lineStyle: EdgeLineStyle? = nil,
        arrowHeads: EdgeArrowHeads? = nil,
        color: TopicColor? = nil
    ) {
        self.id = id
        self.mapID = mapID
        self.sourceNodeID = sourceNodeID
        self.targetNodeID = targetNodeID
        self.edgeType = edgeType
        self.label = label
        self.lineStyle = lineStyle
        self.arrowHeads = arrowHeads
        self.color = color
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

public enum EdgeType: String, Hashable, Sendable, Codable, CaseIterable {
    /// Two ideas are related.
    case relationship
    /// One idea cites or points to another.
    case reference
}

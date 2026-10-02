import Foundation

/// A thought in a map. Hierarchy is `parentID` plus `sortOrder`; canvas position
/// is never stored here, because layout is derived from the graph.
public struct MindNode: Identifiable, Hashable, Sendable, Codable {
    public let id: NodeID
    public let mapID: MapID
    public var parentID: NodeID?
    public var title: String
    public var note: String?
    /// Position among siblings. Fractional, so moving or inserting a node rewrites
    /// only that node, which keeps sync changes small and conflicts rare.
    public var sortOrder: Double
    public var isCollapsed: Bool
    public var nodeType: NodeType
    public var metadata: NodeMetadata
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: NodeID = NodeID(),
        mapID: MapID,
        parentID: NodeID?,
        title: String,
        note: String? = nil,
        sortOrder: Double = 0,
        isCollapsed: Bool = false,
        nodeType: NodeType = .topic,
        metadata: NodeMetadata = NodeMetadata(),
        createdAt: Date = .now,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.mapID = mapID
        self.parentID = parentID
        self.title = title
        self.note = note
        self.sortOrder = sortOrder
        self.isCollapsed = isCollapsed
        self.nodeType = nodeType
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

public enum NodeType: String, Hashable, Sendable, Codable, CaseIterable {
    case topic
}

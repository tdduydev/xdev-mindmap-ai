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
    /// Nil follows the theme's branch colour.
    public var color: TopicColor?
    /// An SF Symbol name or one emoji, shown before the title (`TopicSymbol`).
    public var symbol: String?
    /// Nil when the topic is not a task.
    public var taskState: TaskState?
    public var priority: TaskPriority?
    public var startDate: CalendarDay?
    public var dueDate: CalendarDay?
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
        updatedAt: Date? = nil,
        color: TopicColor? = nil,
        symbol: String? = nil,
        taskState: TaskState? = nil,
        priority: TaskPriority? = nil,
        startDate: CalendarDay? = nil,
        dueDate: CalendarDay? = nil
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
        self.color = color
        self.symbol = symbol
        self.taskState = taskState
        self.priority = priority
        self.startDate = startDate
        self.dueDate = dueDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

public enum NodeType: String, Hashable, Sendable, Codable, CaseIterable {
    case topic
}

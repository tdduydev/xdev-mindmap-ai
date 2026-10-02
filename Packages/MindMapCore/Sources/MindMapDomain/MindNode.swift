import Foundation

/// A thought in a map. Hierarchy is `parentID` plus `sortOrder`; canvas position
/// is derived from the graph, except a floating topic's (ADR 0010).
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
    /// A web or mail link opened from the topic (FR-ORG-26).
    public var link: TopicLink?
    /// Only on a floating topic: `parentID` nil and not the central topic.
    /// Anywhere else it is a stray that `GraphRepair` clears.
    public var position: TopicPosition?
    /// A short remark drawn beside the topic (`MindNode.normalizedCallout`).
    public var callout: String?
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
        dueDate: CalendarDay? = nil,
        link: TopicLink? = nil,
        position: TopicPosition? = nil,
        callout: String? = nil
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
        self.link = link
        self.position = position
        self.callout = callout
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

/// Only `topic` exists: floating and summary topics are told apart by the
/// graph, not by a type (docs/data-model.md, *Node types*). A struct, so a
/// type written by a newer build is kept instead of rewritten as `topic`.
public struct NodeType: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let topic = NodeType(rawValue: "topic")
}

extension MindNode {
    public static let maximumCalloutLength = 280

    /// Trimmed and cut to `maximumCalloutLength` characters; nil for blank text.
    public static func normalizedCallout(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maximumCalloutLength))
    }

    /// Parentless and not the central topic, with a stored position.
    public func isFloating(rootID: NodeID?) -> Bool {
        parentID == nil && id != rootID && position != nil
    }
}

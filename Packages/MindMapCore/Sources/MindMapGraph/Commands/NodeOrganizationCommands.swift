import Foundation
import MindMapDomain

/// Sets the colour, the symbol, or both on one or many topics: one undo step,
/// "Change Color" or "Change Symbol".
public struct SetNodeStyleCommand: GraphCommand {
    public let nodeIDs: [NodeID]
    public let color: FieldChange<TopicColor?>
    /// Normalized with `TopicSymbol.normalized`; blank clears it.
    public let symbol: FieldChange<String?>

    public init(nodeIDs: [NodeID], color: FieldChange<TopicColor?> = .keep, symbol: FieldChange<String?> = .keep) {
        self.nodeIDs = nodeIDs
        self.color = color
        self.symbol = symbol
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        let symbol = symbol.map { $0.flatMap(TopicSymbol.normalized) }
        for id in nodeIDs {
            try transaction.updateNode(id) { node in
                color.apply(to: &node.color)
                symbol.apply(to: &node.symbol)
            }
        }
    }
}

/// Sets task fields on one or many topics. Removing the task (`state: .set(nil)`)
/// keeps priority and dates, so making it a task again loses nothing.
public struct SetTaskCommand: GraphCommand {
    public let nodeIDs: [NodeID]
    public let state: FieldChange<TaskState?>
    public let priority: FieldChange<TaskPriority?>
    public let startDate: FieldChange<CalendarDay?>
    public let dueDate: FieldChange<CalendarDay?>

    public init(
        nodeIDs: [NodeID],
        state: FieldChange<TaskState?> = .keep,
        priority: FieldChange<TaskPriority?> = .keep,
        start startDate: FieldChange<CalendarDay?> = .keep,
        due dueDate: FieldChange<CalendarDay?> = .keep
    ) {
        self.nodeIDs = nodeIDs
        self.state = state
        self.priority = priority
        self.startDate = startDate
        self.dueDate = dueDate
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        for id in nodeIDs {
            try transaction.updateNode(id) { node in
                state.apply(to: &node.taskState)
                priority.apply(to: &node.priority)
                startDate.apply(to: &node.startDate)
                dueDate.apply(to: &node.dueDate)
            }
        }
    }
}

/// Sets or removes the URL link of one or many topics (FR-ORG-26): one undo
/// step, "Add Link", "Edit Link" or "Remove Link" as the session names it.
/// Takes a value already checked with `TopicLink.validated`; setting the same
/// value changes nothing.
public struct SetNodeLinkCommand: GraphCommand {
    public let nodeIDs: [NodeID]
    public let link: TopicLink?

    public init(nodeIDs: [NodeID], link: TopicLink?) {
        self.nodeIDs = nodeIDs
        self.link = link
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        for id in nodeIDs {
            try transaction.updateNode(id) { $0.link = link }
        }
    }
}

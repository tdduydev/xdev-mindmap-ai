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

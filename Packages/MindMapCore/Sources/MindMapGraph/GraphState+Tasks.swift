import Foundation
import MindMapDomain

/// Done over total for the leaf tasks of a branch: tasks with no task below
/// them (docs/node-organization.md, *Tasks*). Computed on every read, never
/// stored, so it cannot go stale or conflict across devices.
public struct TaskProgress: Hashable, Sendable {
    public var done: Int
    public var total: Int

    public init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }

    public var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
    public var isComplete: Bool { total > 0 && done == total }

    static func + (lhs: TaskProgress, rhs: TaskProgress) -> TaskProgress {
        TaskProgress(done: lhs.done + rhs.done, total: lhs.total + rhs.total)
    }

    static let none = TaskProgress(done: 0, total: 0)
}

extension GraphState {
    /// Progress for every topic with a task among its descendants; topics
    /// without one are left out. One pass over the map, children before
    /// parents, with an explicit stack so a deep map cannot overflow it.
    public func taskProgressByNode() -> [NodeID: TaskProgress] {
        guard nodes.values.contains(where: { $0.taskState != nil }) else { return [:] }
        var progress: [NodeID: TaskProgress] = [:]
        // What a branch adds to its parent: its own leaf tasks, or itself when it is a leaf task.
        var subtree: [NodeID: TaskProgress] = [:]
        var visited: Set<NodeID> = []
        for top in topLevelIDs {
            var stack: [(id: NodeID, expanded: Bool)] = [(top, false)]
            while let (id, expanded) = stack.popLast() {
                if expanded {
                    let below = childIDs(of: id).reduce(TaskProgress.none) { $0 + (subtree[$1] ?? .none) }
                    if below.total > 0 {
                        progress[id] = below
                        subtree[id] = below
                    } else if let state = nodes[id]?.taskState {
                        subtree[id] = TaskProgress(done: state.isDone ? 1 : 0, total: 1)
                    }
                    continue
                }
                guard nodes[id] != nil, visited.insert(id).inserted else { continue }
                stack.append((id, true))
                stack.append(contentsOf: childIDs(of: id).map { ($0, false) })
            }
        }
        return progress
    }

    /// Progress of one topic's branch, nil when no task is below it.
    public func taskProgress(of id: NodeID) -> TaskProgress? {
        taskProgressByNode()[id]
    }
}

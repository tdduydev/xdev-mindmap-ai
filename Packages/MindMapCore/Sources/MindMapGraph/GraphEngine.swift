import Foundation
import MindMapDomain

/// Runs commands against one map's graph, keeps it valid, and keeps undo history.
///
/// A value type with no UI, storage or AI dependencies: the editor owns one and
/// hands each returned change set to the repository to save.
public struct GraphEngine: Sendable {
    public private(set) var state: GraphState
    private var history: CommandHistory
    private let clock: @Sendable () -> Date

    /// Fails if the graph is invalid; run `GraphRepair` on loaded data first.
    public init(
        state: GraphState,
        historyLimit: Int = 200,
        clock: @escaping @Sendable () -> Date = { .now }
    ) throws {
        let issues = GraphValidator.validate(state)
        guard issues.isEmpty else { throw GraphError.invalidGraph(issues) }
        self.state = state
        self.history = CommandHistory(limit: historyLimit)
        self.clock = clock
    }

    public var canUndo: Bool { history.canUndo }
    public var canRedo: Bool { history.canRedo }

    /// Runs a command as one undo step and returns what it changed. A command
    /// that changes nothing returns an empty set and leaves history alone.
    @discardableResult
    public mutating func execute(_ command: any GraphCommand) throws -> GraphChangeSet {
        let now = clock()
        var transaction = GraphTransaction(state: state, now: now)
        try command.execute(in: &transaction)

        let changes = transaction.changes
        guard !changes.isEmpty else { return changes }

        // Commands check their own preconditions; this is the safety net that
        // keeps a buggy command, or a malformed AI proposal turned into
        // commands, from ever saving a broken graph.
        var next = transaction.state
        let issues = GraphValidator.validate(next)
        guard issues.isEmpty else { throw GraphError.invalidGraph(issues) }

        next.touch(at: now)
        state = next
        history.record(changes)
        return changes
    }

    /// Reverts the last step and returns the change set that did it.
    @discardableResult
    public mutating func undo() -> GraphChangeSet? {
        guard let changes = history.popUndo() else { return nil }
        let reversed = changes.reversed()
        state.apply(reversed)
        state.touch(at: clock())
        return reversed
    }

    @discardableResult
    public mutating func redo() -> GraphChangeSet? {
        guard let changes = history.popRedo() else { return nil }
        state.apply(changes)
        state.touch(at: clock())
        return changes
    }
}

/// Linear undo history of recorded change sets, capped so a long session
/// cannot grow memory without bound.
struct CommandHistory: Sendable {
    let limit: Int
    private var undoStack: [GraphChangeSet] = []
    private var redoStack: [GraphChangeSet] = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    mutating func record(_ changes: GraphChangeSet) {
        undoStack.append(changes)
        if undoStack.count > limit {
            undoStack.removeFirst(undoStack.count - limit)
        }
        redoStack.removeAll()
    }

    mutating func popUndo() -> GraphChangeSet? {
        guard let changes = undoStack.popLast() else { return nil }
        redoStack.append(changes)
        return changes
    }

    mutating func popRedo() -> GraphChangeSet? {
        guard let changes = redoStack.popLast() else { return nil }
        undoStack.append(changes)
        return changes
    }
}

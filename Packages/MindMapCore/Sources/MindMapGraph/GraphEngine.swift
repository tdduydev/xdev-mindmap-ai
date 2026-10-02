import Foundation
import MindMapDomain

/// Runs commands against one map's graph, keeps it valid, and keeps undo history.
///
/// A value type with no UI, storage or AI dependencies: the editor owns one and
/// hands each returned change set to the repository to save.
public struct GraphEngine: Sendable {
    // Internal setters for `apply(_: LibraryTagChange)`, in its own file.
    public internal(set) var state: GraphState
    var history: CommandHistory
    /// Image bytes the editor has loaded (the graph holds none). A command that
    /// removes one of these images records its bytes, so undo brings it back;
    /// the editor fills this before a step that can remove an image
    /// (`GraphState.images(inBranchesOf:)`). Bytes a step carries (an added
    /// image) are kept here too, so removing that image later, in the same
    /// session, can be undone without asking the store.
    public var imageData: [ImageID: Data] = [:]
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

    /// Names of the steps Undo can take, oldest first, as `execute` got them.
    /// The window rebuilds its undo actions from these after a change from
    /// outside drops some steps (`takeStored`).
    public var undoStepNames: [String?] { history.undoNames }

    /// Runs a command as one undo step and returns what it changed. A command
    /// that changes nothing returns an empty set and leaves history alone.
    /// `name` is kept with the step, for the Edit menu.
    @discardableResult
    public mutating func execute(_ command: any GraphCommand, named name: String? = nil) throws -> GraphChangeSet {
        let now = clock()
        var transaction = GraphTransaction(state: state, now: now, imageData: imageData)
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
        history.record(changes, named: name)
        keepImageData(of: changes)
        return changes
    }

    /// Forgets every undo and redo step.
    public mutating func clearHistory() {
        history.clear()
    }

    /// Reverts the last step and returns the change set that did it.
    @discardableResult
    public mutating func undo() -> GraphChangeSet? {
        guard let changes = history.popUndo() else { return nil }
        return step(applying: changes.reversed())
    }

    @discardableResult
    public mutating func redo() -> GraphChangeSet? {
        guard let changes = history.popRedo() else { return nil }
        return step(applying: changes)
    }

    /// Steps kept across a change from outside were checked against what it
    /// touched, but not against every rule, so each one is validated before
    /// it lands. One that would break the graph clears history instead and
    /// changes nothing; without such a change, steps replay as recorded.
    private mutating func step(applying changes: GraphChangeSet) -> GraphChangeSet? {
        if history.isPruned {
            var next = state
            next.apply(changes)
            guard GraphValidator.validate(next).isEmpty else {
                history.clear()
                return nil
            }
            state = next
        } else {
            // Copying a 10,000-topic state on every undo is not needed here.
            state.apply(changes)
        }
        state.touch(at: clock())
        keepImageData(of: changes)
        return changes
    }

    private mutating func keepImageData(of changes: GraphChangeSet) {
        for (id, change) in changes.images {
            if let data = change.after?.data ?? change.before?.data { imageData[id] = data }
        }
    }
}

/// Linear undo history of recorded change sets, capped so a long session
/// cannot grow memory without bound.
struct CommandHistory: Sendable {
    struct Step: Sendable {
        let changes: GraphChangeSet
        let name: String?
    }

    let limit: Int
    private(set) var undoStack: [Step] = []
    private(set) var redoStack: [Step] = []
    /// Some steps were dropped after a change from outside, so the ones left
    /// no longer form an unbroken chain back to the opened map.
    private(set) var isPruned = false

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var undoNames: [String?] { undoStack.map(\.name) }

    mutating func record(_ changes: GraphChangeSet, named name: String? = nil) {
        undoStack.append(Step(changes: changes, name: name))
        if undoStack.count > limit {
            undoStack.removeFirst(undoStack.count - limit)
        }
        redoStack.removeAll()
    }

    mutating func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
        isPruned = false
    }

    mutating func popUndo() -> GraphChangeSet? {
        guard let step = undoStack.popLast() else { return nil }
        redoStack.append(step)
        return step.changes
    }

    mutating func popRedo() -> GraphChangeSet? {
        guard let step = redoStack.popLast() else { return nil }
        undoStack.append(step)
        return step.changes
    }

    /// Keeps the undo steps `keep` accepts, in order, and empties redo.
    mutating func retainUndoSteps(where keep: (Int) -> Bool) {
        undoStack = undoStack.indices.filter(keep).map { undoStack[$0] }
        redoStack.removeAll()
        isPruned = true
    }
}

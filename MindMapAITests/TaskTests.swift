import CoreGraphics
import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import MindMapInterchange
import MindMapPersistence
import Testing

/// MM-35: a topic as a task, its box, priority and dates as named commands
/// that undo and redo, progress computed from the branch, and overdue shown
/// with more than colour.
@Suite("Tasks")
struct TaskTests {
    let repository: SwiftDataMapRepository
    private struct OpenFailed: Error {}

    init() throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
    }

    /// "Plan" with A and B under the central topic.
    private func open() async throws -> EditorSession {
        var engine = try GraphEngine(state: GraphState.newMap(title: "Plan"))
        let rootID = try #require(engine.state.map.rootNodeID)
        try engine.execute(AddNodeCommand(.child(of: rootID), title: "A"))
        try engine.execute(AddNodeCommand(.child(of: rootID), title: "B"))
        try await repository.create(engine.state)
        guard case .ready(let session) = await EditorSession.open(mapID: engine.state.map.id, repository: repository, onMapChange: { _ in }) else {
            throw OpenFailed()
        }
        return session
    }

    private func node(_ title: String, in session: EditorSession) throws -> NodeID {
        try #require(session.engine.state.nodes.values.first { $0.title == title }?.id)
    }

    private func undoManager(for session: EditorSession) -> UndoManager {
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        session.undoManager = undoManager
        return undoManager
    }

    private func step(_ undoManager: UndoManager, _ action: () -> Void) {
        undoManager.beginUndoGrouping()
        action()
        undoManager.endUndoGrouping()
    }

    @Test func makeTaskAndDoneAreNamedStepsThatUndoAndRedo() async throws {
        let session = try await open()
        let undoManager = undoManager(for: session)
        let a = try node("A", in: session)
        session.selection = a

        step(undoManager) { session.toggleTask() }
        #expect(session.selectedNode?.taskState == .open)
        #expect(undoManager.undoActionName == String(localized: "Make Task"))
        #expect(session.areAllTasks())

        step(undoManager) { session.toggleDone() }
        #expect(session.selectedNode?.taskState == .done)
        #expect(undoManager.undoActionName == String(localized: "Mark as Done"))

        undoManager.undo()
        #expect(session.selectedNode?.taskState == .open)
        undoManager.undo()
        #expect(session.selectedNode?.taskState == nil)
        undoManager.redo()
        #expect(session.selectedNode?.taskState == .open)
        undoManager.redo()
        #expect(session.selectedNode?.taskState == .done)

        step(undoManager) { session.toggleTask() }
        #expect(session.selectedNode?.taskState == nil)
        #expect(undoManager.undoActionName == String(localized: "Remove Task"))
    }

    @Test func removingTheTaskKeepsPriorityAndDates() async throws {
        let session = try await open()
        let a = try node("A", in: session)
        let due = try #require(CalendarDay(isoString: "2026-10-09"))
        session.selection = a
        session.toggleTask()
        session.choosePriority(.high)
        session.setDueDate(due, for: [a])

        session.toggleTask()

        #expect(session.selectedNode?.taskState == nil)
        #expect(session.selectedNode?.priority == .high)
        #expect(session.selectedNode?.dueDate == due)
    }

    @Test func multiSelectionIsOneStep() async throws {
        let session = try await open()
        let undoManager = undoManager(for: session)
        let a = try node("A", in: session)
        let b = try node("B", in: session)
        session.setSelection([a, b], primary: a)

        step(undoManager) { session.toggleTask() }
        #expect(session.engine.state.node(a)?.taskState == .open)
        #expect(session.engine.state.node(b)?.taskState == .open)

        undoManager.undo()
        #expect(session.engine.state.node(a)?.taskState == nil)
        #expect(session.engine.state.node(b)?.taskState == nil)
        undoManager.redo()
        #expect(session.engine.state.node(b)?.taskState == .open)
    }

    @Test func thePriorityKeyAgainClearsIt() async throws {
        let session = try await open()
        let undoManager = undoManager(for: session)
        session.selection = try node("A", in: session)

        step(undoManager) { session.choosePriority(.medium) }
        #expect(session.selectedNode?.priority == .medium)
        #expect(undoManager.undoActionName == String(localized: "Set Priority"))
        step(undoManager) { session.choosePriority(.medium) }
        #expect(session.selectedNode?.priority == nil)
        #expect(undoManager.undoActionName == String(localized: "Remove Priority"))

        undoManager.undo()
        #expect(session.selectedNode?.priority == .medium)
        undoManager.redo()
        #expect(session.selectedNode?.priority == nil)
    }

    @Test func datesSetAndClearAsSteps() async throws {
        let session = try await open()
        let undoManager = undoManager(for: session)
        let a = try node("A", in: session)
        let start = try #require(CalendarDay(isoString: "2026-10-01"))
        let due = try #require(CalendarDay(isoString: "2026-10-09"))
        session.selection = a

        step(undoManager) { session.setStartDate(start, for: [a]) }
        step(undoManager) { session.setDueDate(due, for: [a]) }
        #expect(undoManager.undoActionName == String(localized: "Set Due Date"))
        step(undoManager) { session.setDueDate(nil, for: [a]) }
        #expect(undoManager.undoActionName == String(localized: "Clear Due Date"))

        undoManager.undo()
        #expect(session.selectedNode?.dueDate == due)
        undoManager.undo()
        #expect(session.selectedNode?.dueDate == nil)
        #expect(session.selectedNode?.startDate == start)
        undoManager.redo()
        #expect(session.selectedNode?.dueDate == due)
    }

    @Test func theCheckboxMakesATaskDoneInOneStep() async throws {
        let session = try await open()
        let undoManager = undoManager(for: session)
        let b = try node("B", in: session)

        step(undoManager) { session.toggleDone(b) }
        #expect(session.engine.state.node(b)?.taskState == .done)
        undoManager.undo()
        #expect(session.engine.state.node(b)?.taskState == nil)
        undoManager.redo()
        #expect(session.engine.state.node(b)?.taskState == .done)
    }

    @Test func overdueIsBeforeTodayAndNotDone() throws {
        let today = try #require(CalendarDay(isoString: "2026-10-03"))
        let yesterday = try #require(CalendarDay(isoString: "2026-10-02"))
        #expect(CalendarDay.isOverdue(yesterday, state: .open, today: today))
        #expect(!CalendarDay.isOverdue(yesterday, state: .done, today: today))
        #expect(!CalendarDay.isOverdue(today, state: .open, today: today))
        #expect(!CalendarDay.isOverdue(yesterday, state: nil, today: today))
    }

    @Test func canvasDrawsTaskChipsAndProgressAndMeasuresThem() async throws {
        let session = try await open()
        let canvas = CanvasModel(session: session)
        canvas.setTextSpecs(.designSizes())
        await canvas.layoutSettled()
        let rootID = try #require(session.rootID)
        let a = try node("A", in: session)
        let b = try node("B", in: session)
        let before = try #require(canvas.scene.topic(a)?.frame.size)

        session.setSelection([a, b], primary: a)
        session.toggleTask()
        session.toggleDone(a)
        session.selection = a
        session.choosePriority(.high)
        session.setDueDate(CalendarDay(isoString: "2000-01-01"), for: [a, b])
        await canvas.layoutSettled()

        let topic = try #require(canvas.scene.topic(a))
        #expect(topic.chips.first?.kind == .checkbox(done: true))
        #expect(topic.chips.map(\.label).contains("!!!"))
        #expect(topic.frame.height > before.height, "the task chips are part of the box")
        #expect(!topic.isOverdue, "a done task is never overdue")
        let other = try #require(canvas.scene.topic(b))
        #expect(other.isOverdue)
        let date = try #require(CalendarDay(isoString: "2000-01-01")).shortText(today: .today())
        let overdueLabel = String(localized: "Overdue \(date)")
        #expect(other.chips.contains { $0.kind == .due(overdue: true) && $0.label == overdueLabel }, "a word, not only colour")
        let root = try #require(canvas.scene.topic(rootID))
        #expect(root.progress == TaskProgress(done: 1, total: 2))
        #expect(root.chips.contains { $0.label == "1/2" })
    }

    @Test func outlineRowsCarryProgress() async throws {
        let session = try await open()
        let a = try node("A", in: session)
        session.toggleDone(a)

        let root = try #require(session.rows.first)
        #expect(root.progress == TaskProgress(done: 1, total: 1))
    }

    @Test func copyWritesMarkdownTaskBoxes() async throws {
        let session = try await open()
        let a = try node("A", in: session)
        session.toggleDone(a)
        session.selection = a

        #expect(session.selectionMarkdown?.contains("[x] A") == true)
    }
}

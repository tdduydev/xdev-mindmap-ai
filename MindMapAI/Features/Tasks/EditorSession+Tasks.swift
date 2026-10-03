import Foundation
import MindMapDomain
import MindMapGraph

// Task fields on topics (MM-35, docs/node-organization.md *Tasks*). Every
// action applies to the whole selection as one `SetTaskCommand`, so a
// multi-selection is one undo step; progress is read from the graph, never set.
extension EditorSession {
    var canEditSelectionTask: Bool { !orderedSelection.isEmpty }

    private func tasks(in ids: [NodeID]) -> [MindNode] {
        ids.compactMap { engine.state.node($0) }.filter { $0.taskState != nil }
    }

    /// Make Task or Remove Task: Remove when every topic is a task.
    func areAllTasks(_ ids: [NodeID]? = nil) -> Bool {
        let ids = ids ?? orderedSelection
        return !ids.isEmpty && tasks(in: ids).count == ids.count
    }

    /// Mark as Done applies once any of the topics is a task.
    func hasTask(_ ids: [NodeID]? = nil) -> Bool {
        !tasks(in: ids ?? orderedSelection).isEmpty
    }

    /// Mark as Not Done when every task among the topics is done.
    func areTasksDone(_ ids: [NodeID]? = nil) -> Bool {
        let tasks = tasks(in: ids ?? orderedSelection)
        return !tasks.isEmpty && tasks.allSatisfy { $0.taskState?.isDone == true }
    }

    /// The priority every topic shares, nil when none or mixed.
    func sharedPriority(_ ids: [NodeID]? = nil) -> TaskPriority? {
        let levels = Set((ids ?? orderedSelection).compactMap { engine.state.node($0) }.map { $0.priority?.level })
        return levels.count == 1 ? levels.first ?? nil : nil
    }

    /// Make Task on topics that are not, or Remove Task when all are. Remove
    /// keeps priority and dates, so making it a task again loses nothing.
    func toggleTask(_ ids: [NodeID]? = nil) {
        let ids = ids ?? orderedSelection
        guard !ids.isEmpty else { return }
        if areAllTasks(ids) {
            perform(SetTaskCommand(nodeIDs: ids, state: .set(nil)), named: String(localized: "Remove Task"))
        } else {
            let topics = ids.filter { engine.state.node($0)?.taskState == nil }
            perform(SetTaskCommand(nodeIDs: topics, state: .set(.open)), named: String(localized: "Make Task"))
        }
    }

    func toggleTask(_ id: NodeID) {
        toggleTask([id])
    }

    /// Mark as Done on the tasks, or Mark as Not Done when all are done.
    func toggleDone(_ ids: [NodeID]? = nil) {
        let ids = ids ?? orderedSelection
        let tasks = tasks(in: ids).map(\.id)
        guard !tasks.isEmpty else { return }
        setDone(!areTasksDone(ids), for: tasks)
    }

    /// The checkbox on the canvas and in the outline. A topic that is not a
    /// task yet becomes one, done.
    func toggleDone(_ id: NodeID) {
        guard let node = engine.state.node(id) else { return }
        setDone(node.taskState?.isDone != true, for: [id])
    }

    private func setDone(_ done: Bool, for ids: [NodeID]) {
        let name = done ? String(localized: "Mark as Done") : String(localized: "Mark as Not Done")
        perform(SetTaskCommand(nodeIDs: ids, state: .set(done ? .done : .open)), named: name)
    }

    /// Priority ▸ High, Medium, Low (⌥⌘1–3). Choosing the priority every
    /// topic already has clears it, so the same key turns it off.
    func choosePriority(_ priority: TaskPriority?, for ids: [NodeID]? = nil) {
        let ids = ids ?? orderedSelection
        guard !ids.isEmpty else { return }
        let value = priority != nil && priority == sharedPriority(ids) ? nil : priority
        setPriority(value, for: ids)
    }

    func setPriority(_ priority: TaskPriority?, for ids: [NodeID]) {
        let changed = ids.filter { engine.state.node($0).map { $0.priority?.level != priority } ?? false }
        guard !changed.isEmpty else { return }
        let name = priority == nil ? String(localized: "Remove Priority") : String(localized: "Set Priority")
        perform(SetTaskCommand(nodeIDs: changed, priority: .set(priority)), named: name)
    }

    func setStartDate(_ day: CalendarDay?, for ids: [NodeID]) {
        let changed = ids.filter { engine.state.node($0).map { $0.startDate != day } ?? false }
        guard !changed.isEmpty else { return }
        let name = day == nil ? String(localized: "Clear Start Date") : String(localized: "Set Start Date")
        perform(SetTaskCommand(nodeIDs: changed, start: .set(day)), named: name)
    }

    func setDueDate(_ day: CalendarDay?, for ids: [NodeID]) {
        let changed = ids.filter { engine.state.node($0).map { $0.dueDate != day } ?? false }
        guard !changed.isEmpty else { return }
        let name = day == nil ? String(localized: "Clear Due Date") : String(localized: "Set Due Date")
        perform(SetTaskCommand(nodeIDs: changed, due: .set(day)), named: name)
    }

    /// Topic ▸ Set Task Dates…: the inspector, with its Task section.
    func beginSettingTaskDates() {
        guard canEditSelectionTask else { return }
        isInspectorPresented = true
    }
}

extension TaskPriority {
    /// `!!!` high, `!!` medium, `!` low, as Reminders marks them.
    nonisolated var marks: String { String(repeating: "!", count: 4 - level.rawValue) }

    nonisolated var title: String {
        switch level {
        case .high: String(localized: "High")
        case .medium: String(localized: "Medium")
        default: String(localized: "Low")
        }
    }

    nonisolated static let menuOrder: [TaskPriority] = [.high, .medium, .low]
}

extension CalendarDay {
    /// Midnight of this day in `calendar`, for date pickers and formatting.
    nonisolated func date(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .now
    }

    /// Before today on this device and not done: the canvas, outline and
    /// VoiceOver all mark it with a symbol and a word, not colour alone.
    nonisolated static func isOverdue(_ due: CalendarDay?, state: TaskState?, today: CalendarDay) -> Bool {
        guard let due, let state, !state.isDone else { return false }
        return due < today
    }

    nonisolated static func today(_ calendar: Calendar = .current) -> CalendarDay {
        CalendarDay(.now, in: calendar)
    }

    /// "3 Oct", or "3 Oct 2027" outside the current year.
    nonisolated func shortText(today: CalendarDay, calendar: Calendar = .current) -> String {
        let date = date(in: calendar)
        var style = Date.FormatStyle.dateTime.day().month(.abbreviated)
        style.timeZone = calendar.timeZone
        return date.formatted(year == today.year ? style : style.year())
    }
}

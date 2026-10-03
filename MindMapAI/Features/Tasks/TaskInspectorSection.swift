import MindMapDomain
import MindMapGraph
import SwiftUI

/// The inspector's Task section (MM-35): Task, Done, Priority, Start and Due
/// with Clear, and the progress of the branch, read-only. Every control acts
/// on the whole selection as one undo step; dates show the primary topic's.
struct TaskInspectorSection: View {
    let session: EditorSession
    let node: MindNode

    var body: some View {
        let ids = session.orderedSelection
        Toggle("Task", isOn: Binding(
            get: { session.areAllTasks(ids) },
            set: { _ in session.toggleTask(ids) }
        ))
        .accessibilityIdentifier(AccessibilityID.Task.isTask)
        if session.hasTask(ids) {
            Toggle("Done", isOn: Binding(
                get: { session.areTasksDone(ids) },
                set: { _ in session.toggleDone(ids) }
            ))
            .accessibilityIdentifier(AccessibilityID.Task.done)
        }
        Picker("Priority", selection: Binding(
            get: { session.sharedPriority(ids) },
            set: { session.setPriority($0, for: ids) }
        )) {
            Text("None").tag(TaskPriority?.none)
            ForEach(TaskPriority.menuOrder, id: \.self) { priority in
                Text(verbatim: "\(priority.title)  \(priority.marks)").tag(Optional(priority))
            }
        }
        .accessibilityIdentifier(AccessibilityID.Task.priority)
        TaskDateRow(
            title: "Start", addTitle: "Add Start Date", day: node.startDate,
            set: { session.setStartDate($0, for: ids) }
        )
        TaskDateRow(
            title: "Due", addTitle: "Add Due Date", day: node.dueDate,
            isOverdue: CalendarDay.isOverdue(node.dueDate, state: node.taskState, today: .today()),
            set: { session.setDueDate($0, for: ids) }
        )
        if let progress = session.engine.state.taskProgress(of: node.id) {
            LabeledContent("Progress") {
                HStack(spacing: Spacing.sm) {
                    ProgressView(value: progress.fraction)
                        .frame(maxWidth: Metrics.taskProgressBarWidth)
                    Text("\(progress.done) of \(progress.total) done")
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// A date with Clear, or a button that adds today's date.
private struct TaskDateRow: View {
    let title: LocalizedStringKey
    let addTitle: LocalizedStringKey
    let day: CalendarDay?
    var isOverdue = false
    let set: (CalendarDay?) -> Void

    var body: some View {
        if let day {
            HStack {
                DatePicker(title, selection: Binding(
                    get: { day.date(in: .current) },
                    set: { set(CalendarDay($0, in: .current)) }
                ), displayedComponents: .date)
                Button("Clear") { set(nil) }
                    .buttonStyle(.borderless)
            }
            if isOverdue {
                // A symbol and a word as well as the colour (WCAG 1.4.1).
                Label("Overdue", systemImage: "exclamationmark.circle")
                    .foregroundStyle(Palette.danger)
                    .accessibilityIdentifier(AccessibilityID.Task.overdue)
            }
        } else {
            Button(addTitle) { set(.today()) }
        }
    }
}

/// The due date as VoiceOver custom content ("more content"); overdue is in the value.
struct TaskDateCustomContent: ViewModifier {
    let due: CalendarDay?

    func body(content: Content) -> some View {
        if let due {
            content.accessibilityCustomContent(Text("Due"), Text(due.date(in: .current), format: .dateTime.day().month().year()))
        } else {
            content
        }
    }
}

/// The task box before an outline row's title; a click toggles done.
struct OutlineTaskBox: View {
    let isDone: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isDone ? "checkmark.square.fill" : "square")
                .foregroundStyle(.secondary)
                .frame(minWidth: Metrics.minimumHitTarget, minHeight: Metrics.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isDone ? Text("Mark as Not Done") : Text("Mark as Done"))
        .accessibilityIdentifier(AccessibilityID.Task.checkbox)
        // The row reads the state in its value and has Mark as Done.
        .accessibilityHidden(true)
    }
}

/// Priority, progress and due date after an outline row's title.
struct OutlineTaskDetails: View {
    let node: MindNode
    let progress: TaskProgress?
    let today: CalendarDay

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let priority = node.priority {
                Text(verbatim: priority.marks)
                    .fontWeight(.semibold)
            }
            if let progress {
                Text(verbatim: "\(progress.done)/\(progress.total)")
            }
            if let due = node.dueDate, node.taskState != nil || progress != nil {
                let overdue = CalendarDay.isOverdue(due, state: node.taskState, today: today)
                Label(due.shortText(today: today), systemImage: overdue ? "exclamationmark.circle" : "calendar")
                    .foregroundStyle(overdue ? Palette.danger : .secondary)
            }
        }
        .font(Typography.rowDetail)
        .foregroundStyle(.secondary)
        .fixedSize()
        .accessibilityHidden(true)
    }
}

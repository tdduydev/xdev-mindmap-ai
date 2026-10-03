import MindMapDomain
import MindMapGraph
import SwiftUI

/// The topic context menu's Task: the same items as Topic ▸ Make Task, Mark
/// as Done and Priority, without keys, which the menu bar carries
/// (`MapCommands`) so they are not registered twice.
struct TaskMenu: View {
    let session: EditorSession
    /// The topics the items act on; the selection when nil.
    var targets: [NodeID]?

    var body: some View {
        Menu("Task") {
            Button(session.areAllTasks(targets) ? "Remove Task" : "Make Task") { session.toggleTask(targets) }
            Button(session.areTasksDone(targets) ? "Mark as Not Done" : "Mark as Done") { session.toggleDone(targets) }
                .disabled(!session.hasTask(targets))
            Divider()
            PriorityPicker(session: session, targets: targets)
            Button("Set Task Dates…") {
                if let targets, let first = targets.first, !session.isSelected(first) { session.selection = first }
                session.beginSettingTaskDates()
            }
        }
        .disabled((targets ?? session.orderedSelection).isEmpty)
    }
}

/// Priority ▸ High, Medium, Low, None, checked by the priority the topics share.
struct PriorityPicker: View {
    let session: EditorSession
    var targets: [NodeID]?
    /// The menu bar gives High, Medium and Low ⌥⌘1–3.
    var showsShortcuts = false

    var body: some View {
        Menu("Priority") {
            ForEach(TaskPriority.menuOrder, id: \.self) { priority in
                Toggle(isOn: binding(for: priority)) {
                    Text(verbatim: "\(priority.title)  \(priority.marks)")
                }
                .keyboardShortcut(showsShortcuts ? KeyboardShortcut(KeyEquivalent(Character("\(priority.rawValue)")), modifiers: [.command, .option]) : nil)
            }
            Divider()
            Button("None") { session.setPriority(nil, for: targets ?? session.orderedSelection) }
                .disabled(session.sharedPriority(targets) == nil && !(targets ?? session.orderedSelection).contains { session.engine.state.node($0)?.priority != nil })
        }
        .disabled((targets ?? session.orderedSelection).isEmpty)
    }

    private func binding(for priority: TaskPriority) -> Binding<Bool> {
        Binding(
            get: { session.sharedPriority(targets) == priority },
            set: { _ in session.choosePriority(priority, for: targets) }
        )
    }
}

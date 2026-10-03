import MindMapDomain
import MindMapGraph
import MindMapSearch
import SwiftUI

/// View ▸ Show Filter Bar (⌥⌘L): one menu per criterion, a text field, Dim or
/// Hide Others and the match count. It sits above the canvas or the outline,
/// like the find bar. View state only: nothing here is a command or synced.
struct FilterBar: View {
    @Bindable var session: EditorSession

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "line.3.horizontal.decrease")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    tagsMenu
                    criterionMenu("Priority", selected: session.filter.priorities.count) {
                        ForEach([TaskPriority.high, .medium, .low], id: \.self) { priority in
                            Toggle(priority.title, isOn: binding(priority, \.priorities))
                        }
                    }
                    criterionMenu("Status", selected: session.filter.tasks.count) {
                        ForEach(MapFilter.TaskChoice.allCases, id: \.self) { choice in
                            Toggle(choice.title, isOn: binding(choice, \.tasks))
                        }
                    }
                    criterionMenu("Due", selected: session.filter.due.count) {
                        ForEach(MapFilter.DueChoice.allCases, id: \.self) { choice in
                            Toggle(choice.title, isOn: binding(choice, \.due))
                        }
                    }
                    criterionMenu("Origin", selected: session.filter.origins.count) {
                        ForEach(NodeOrigin.allCases, id: \.self) { origin in
                            Toggle(origin.filterTitle, isOn: binding(origin, \.origins))
                        }
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            TextField("Filter by text or #tag", text: $session.filter.text, prompt: Text("Filter by text or #tag"))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .frame(minWidth: Metrics.minimumHitTarget * 3)
                .accessibilityIdentifier(AccessibilityID.Filter.text)
            Picker("Others", selection: $session.filterMode) {
                Text("Dim Others").tag(FilterMode.dim)
                Text("Hide Others").tag(FilterMode.hide)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .accessibilityIdentifier(AccessibilityID.Filter.mode)
            if session.filter.isActive {
                let counts = session.filterCounts
                Text("\(counts.matches) of \(counts.total) topics")
                    .font(Typography.rowDetail)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize()
                    .accessibilityIdentifier(AccessibilityID.Filter.count)
                Button("Clear", action: session.clearFilter)
                    .accessibilityIdentifier(AccessibilityID.Filter.clear)
            }
            Button("Done", action: session.toggleFilterBar)
                .keyboardShortcut(.cancelAction)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Filter"))
        .accessibilityIdentifier(AccessibilityID.Filter.bar)
    }

    private var tagsMenu: some View {
        let tags = session.engine.state.tags.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return criterionMenu("Tags", selected: session.filter.tagIDs.count) {
            Picker("Match", selection: $session.filter.tagMatch) {
                Text("Any Tag").tag(MapFilter.TagMatch.any)
                Text("All Tags").tag(MapFilter.TagMatch.all)
            }
            .pickerStyle(.inline)
            Divider()
            if tags.isEmpty {
                Text("No Tags")
            }
            ForEach(tags) { tag in
                Toggle(isOn: binding(tag.id, \.tagIDs)) {
                    Text(verbatim: tag.name)
                }
            }
        }
    }

    /// "Priority" or "Priority (2)": the count says the criterion is on
    /// without relying on a tint.
    private func criterionMenu(
        _ title: LocalizedStringResource,
        selected: Int,
        @ViewBuilder content: () -> some View
    ) -> some View {
        Menu {
            content()
        } label: {
            if selected > 0 {
                Text("\(String(localized: title)) (\(selected))")
            } else {
                Text(title)
            }
        }
        .menuStyle(.button)
        .fixedSize()
        .frame(minHeight: Metrics.minimumHitTarget)
        .accessibilityValue(selected > 0 ? Text("\(selected) selected") : Text("Off"))
    }

    private func binding<Value: Hashable>(_ value: Value, _ criterion: WritableKeyPath<MapFilter, Set<Value>>) -> Binding<Bool> {
        Binding(
            get: { session.filter[keyPath: criterion].contains(value) },
            set: { _ in session.toggleFilter(value, in: criterion) }
        )
    }
}

/// In the toolbar while a filter is on, even with the bar closed: "Filtered"
/// with the count, and a button that clears it.
struct FilterChip: View {
    let session: EditorSession

    var body: some View {
        let counts = session.filterCounts
        HStack(spacing: Spacing.xxs) {
            Button(action: session.toggleFilterBar) {
                Label {
                    Text("Filtered: \(counts.matches) of \(counts.total)")
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                }
                .labelStyle(.titleAndIcon)
            }
            .accessibilityHint(Text("Shows the filter bar"))
            .accessibilityIdentifier(AccessibilityID.Filter.chip)
            Button(action: session.clearFilter) {
                Label("Clear Filter", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: Metrics.minimumHitTarget, minHeight: Metrics.minimumHitTarget)
            }
            .help(Text("Clear Filter"))
            .accessibilityIdentifier(AccessibilityID.Filter.clear)
        }
        .buttonStyle(.borderless)
        .fixedSize()
    }
}

/// Above the canvas while a branch is focused: its ancestors, each one a
/// button that focuses there, and Exit Focus.
struct FocusBreadcrumb: View {
    let session: EditorSession

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "scope")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xxs) {
                    let path = session.focusPath
                    ForEach(Array(path.enumerated()), id: \.element.id) { index, node in
                        if index > 0 {
                            Image(systemName: "chevron.forward")
                                .font(Typography.rowDetail)
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        Button {
                            session.focus(on: node.id)
                        } label: {
                            Text(node.title.isEmpty ? String(localized: "Untitled Topic") : node.title)
                                .lineLimit(1)
                                .frame(minHeight: Metrics.minimumHitTarget)
                        }
                        .disabled(index == path.count - 1)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Focused branch"))
            .accessibilityIdentifier(AccessibilityID.Filter.breadcrumb)
            Button("Exit Focus", action: session.exitFocus)
                .accessibilityIdentifier(AccessibilityID.Filter.exitFocus)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xxs)
        .background(.bar)
    }
}

extension MapFilter.TaskChoice {
    var title: String {
        switch self {
        case .open: String(localized: "Not Done")
        case .done: String(localized: "Done")
        case .notATask: String(localized: "Not a Task")
        }
    }
}

extension MapFilter.DueChoice {
    var title: String {
        switch self {
        case .overdue: String(localized: "Overdue")
        case .today: String(localized: "Due Today")
        case .nextSevenDays: String(localized: "Next 7 Days")
        case .noDate: String(localized: "No Due Date")
        }
    }
}

extension NodeOrigin {
    /// Who made a topic, as the filter offers it.
    var filterTitle: String {
        switch self {
        case .user: String(localized: "Made by You")
        case .ai: String(localized: "Made by AI")
        case .imported: String(localized: "Imported")
        }
    }
}

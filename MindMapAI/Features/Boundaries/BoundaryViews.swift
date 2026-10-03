import MindMapAICore
import MindMapDomain
import MindMapGraph
import SwiftUI

/// Edits a boundary's title in place, over its title band.
struct BoundaryTitleField: View {
    let model: CanvasModel
    let groupID: GroupID
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Title", text: $draft, prompt: Text("Boundary title"))
            .textFieldStyle(.roundedBorder)
            .font(Typography.Content.badge.font)
            .frame(width: CanvasMetrics.boundaryTitleMaxWidth)
            .focused($isFocused)
            .onAppear {
                draft = model.session.engine.state.group(groupID)?.title ?? ""
                isFocused = true
            }
            .onSubmit(finish)
            .onChange(of: isFocused) { _, focused in if !focused { finish() } }
            #if os(macOS)
            .onExitCommand { model.editingBoundaryTitle = nil }
            #endif
            .onKeyPress(.escape) {
                model.editingBoundaryTitle = nil
                return .handled
            }
            .accessibilityLabel(Text("Boundary Title"))
    }

    private func finish() {
        guard model.editingBoundaryTitle == groupID else { return }
        model.editingBoundaryTitle = nil
        model.session.renameBoundary(groupID, to: draft)
    }
}

/// The inspector's Boundary section while a boundary is selected: title,
/// colour and Remove Boundary.
struct BoundaryInspectorSection: View {
    let session: EditorSession
    let groupID: GroupID
    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(session: EditorSession, groupID: GroupID) {
        self.session = session
        self.groupID = groupID
        _draft = State(initialValue: session.engine.state.group(groupID)?.title ?? "")
    }

    var body: some View {
        let group = session.engine.state.group(groupID)
        Section("Boundary") {
            if let range = session.boundaryRangeTitle(groupID) {
                LabeledContent("Topics", value: range)
            }
            TextField("Title", text: $draft, prompt: Text("Boundary title"))
                .focused($isFocused)
                .onSubmit { session.renameBoundary(groupID, to: draft) }
                .onChange(of: isFocused) { _, focused in if !focused { session.renameBoundary(groupID, to: draft) } }
            Picker("Color", selection: Binding(
                get: { group?.color },
                set: { session.setBoundaryColor($0, for: groupID) }
            )) {
                Text("Default").tag(TopicColor?.none)
                ForEach(TopicColor.all, id: \.self) { color in
                    Label(color.title, systemImage: color.shapeSymbol).tag(TopicColor?.some(color))
                }
            }
            Button("Remove Boundary", role: .destructive) { session.removeBoundary(groupID) }
        }
    }
}

/// Format ▸ Boundary Color for the selected boundary, or the one framing
/// the selected topics exactly; disabled, not hidden, without one.
struct BoundaryFormatMenu: View {
    let editor: EditorSession?

    var body: some View {
        let id = editor?.boundaryToRemove
        let group = id.flatMap { editor?.engine.state.group($0) }
        Menu("Boundary Color") {
            Toggle("Default", isOn: Binding(
                get: { group != nil && group?.color == nil },
                set: { _ in if let id { editor?.setBoundaryColor(nil, for: id) } }
            ))
            ForEach(TopicColor.all, id: \.self) { color in
                Toggle(isOn: Binding(
                    get: { group?.color == color },
                    set: { _ in if let id { editor?.setBoundaryColor(color, for: id) } }
                )) {
                    Label(color.title, systemImage: color.shapeSymbol)
                }
            }
        }
        .disabled(group == nil)
    }
}

/// Suggested boundaries or a suggested boundary title, each title editable
/// before Accept, with Discard per group.
struct AIBoundarySuggestionList: View {
    @Bindable var assistant: AIAssistant

    var body: some View {
        if let suggestions = assistant.boundarySuggestions {
            List {
                Section {
                    ForEach(suggestions.groups) { group in
                        AIBoundarySuggestionRow(
                            group: group,
                            members: group.nodeIDs.compactMap { assistant.session.engine.state.node($0)?.title },
                            onRename: { assistant.renameBoundarySuggestion(group.id, to: $0) },
                            onDiscard: { assistant.discardBoundarySuggestion(group.id) }
                        )
                    }
                } header: {
                    Label {
                        Text(suggestions.kind == .title ? AIFeature.summarizeBoundary.suggestionsTitle : AIFeature.suggestGroups.suggestionsTitle)
                    } icon: {
                        AISymbol()
                    }
                } footer: {
                    Text("Suggested by AI on this device. Nothing changes until you accept.")
                }
            }
            .frame(minWidth: Metrics.suggestionListWidth, minHeight: Metrics.suggestionListHeight)
        }
    }
}

private struct AIBoundarySuggestionRow: View {
    let group: BoundarySuggestionState.Group
    let members: [String]
    let onRename: (String) -> Void
    let onDiscard: () -> Void
    @State private var draft: String

    init(group: BoundarySuggestionState.Group, members: [String], onRename: @escaping (String) -> Void, onDiscard: @escaping () -> Void) {
        self.group = group
        self.members = members
        self.onRename = onRename
        self.onDiscard = onDiscard
        _draft = State(initialValue: group.title)
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                TextField("Title", text: $draft)
                    .onSubmit { onRename(draft) }
                if !members.isEmpty {
                    Text(verbatim: members.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button("Discard", systemImage: "xmark", action: onDiscard)
                .labelStyle(.iconOnly)
                .frame(minWidth: Metrics.minimumHitTarget, minHeight: Metrics.minimumHitTarget)
        }
        .onChange(of: draft) { _, title in onRename(title) }
    }
}

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

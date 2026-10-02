import MindMapDomain
import SwiftUI

/// The map as an indented outline: the way to use a map without the canvas,
/// for VoiceOver and the keyboard. Toolbar and menus come from `MapEditorView`.
struct OutlineEditorView: View {
    @Bindable var session: EditorSession
    @FocusState private var focusedNode: NodeID?

    var body: some View {
        List(selection: $session.selection) {
            ForEach(session.rows) { row in
                OutlineRow(
                    row: row,
                    isRoot: row.id == session.rootID,
                    focus: $focusedNode,
                    onRename: { session.rename(row.id, to: $0) },
                    onToggle: { session.toggleCollapsed(row.id) }
                )
            }
        }
        .overlay {
            if session.rows.isEmpty {
                ContentUnavailableView {
                    Label("Empty Map", systemImage: "point.3.connected.trianglepath.dotted")
                } actions: {
                    Button("Add Central Topic", action: session.addRoot)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .onChange(of: session.focusRequest, initial: true) { _, request in
            guard let request else { return }
            focusedNode = request
            session.focusRequest = nil
        }
        .onChange(of: focusedNode) { _, node in
            if let node { session.selection = node }
        }
    }
}

struct OutlineRow: View {
    let row: EditorSession.Row
    let isRoot: Bool
    var focus: FocusState<NodeID?>.Binding
    let onRename: (String) -> Void
    let onToggle: () -> Void
    @State private var draft: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        row: EditorSession.Row,
        isRoot: Bool,
        focus: FocusState<NodeID?>.Binding,
        onRename: @escaping (String) -> Void,
        onToggle: @escaping () -> Void
    ) {
        self.row = row
        self.isRoot = isRoot
        self.focus = focus
        self.onRename = onRename
        self.onToggle = onToggle
        _draft = State(initialValue: row.node.title)
    }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            disclosure
            TextField("Topic", text: $draft, prompt: Text("Untitled Topic"))
                .textFieldStyle(.plain)
                .font(isRoot ? Typography.Content.outlineRoot.font : Typography.Content.outlineTopic.font)
                .focused(focus, equals: row.id)
                .onSubmit(commit)
                .accessibilityLabel(isRoot ? Text("Central Topic") : Text("Topic, level \(row.depth + 1)"))
        }
        .padding(.leading, CGFloat(row.depth) * Spacing.outlineIndent)
        // Undo changes the title from outside; show it unless the user is typing here.
        .onChange(of: row.node.title) { _, title in
            if focus.wrappedValue != row.id { draft = title }
        }
        .onChange(of: focus.wrappedValue) { previous, current in
            if previous == row.id, current != row.id { commit() }
        }
    }

    private var disclosure: some View {
        Button {
            withAnimation(Motion.standard(reduceMotion: reduceMotion), onToggle)
        } label: {
            Image(systemName: "chevron.right")
                .rotationEffect(.degrees(row.node.isCollapsed ? 0 : 90))
                .foregroundStyle(.secondary)
                .frame(width: Metrics.disclosureSize, height: Metrics.disclosureSize)
                .frame(minWidth: Metrics.minimumHitTarget, minHeight: Metrics.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(row.hasChildren ? 1 : 0)
        .disabled(!row.hasChildren)
        .accessibilityHidden(!row.hasChildren)
        .accessibilityLabel(row.node.isCollapsed ? Text("Expand") : Text("Collapse"))
    }

    private func commit() {
        guard draft != row.node.title else { return }
        onRename(draft)
    }
}

struct SaveFailedBanner: View {
    var body: some View {
        Label("Couldn’t save your latest changes.", systemImage: "exclamationmark.triangle.fill")
            .font(Typography.banner)
            .foregroundStyle(Palette.warningText)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .background(Palette.warningFill, in: RoundedRectangle(cornerRadius: Radius.md))
            .padding(Spacing.md)
    }
}

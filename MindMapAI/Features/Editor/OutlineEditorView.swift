import MindMapDomain
import SwiftUI

/// The minimal editor: the map as an indented outline. The canvas replaces it
/// as the main view in a later phase; the outline stays as the accessible one.
struct OutlineEditorView: View {
    @Bindable var session: EditorSession
    @Environment(\.undoManager) private var undoManager
    @FocusState private var focusedNode: NodeID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: $session.selection) {
                ForEach(session.rows) { row in
                    OutlineRow(
                        row: row,
                        isRoot: row.id == session.rootID,
                        isFindMatch: session.findMatchSet.contains(row.id),
                        focus: $focusedNode,
                        onRename: { session.rename(row.id, to: $0) },
                        onToggle: { session.toggleCollapsed(row.id) }
                    )
                }
            }
            .onChange(of: session.scrollRequest) { _, request in
                guard let request else { return }
                withAnimation(Motion.standard(reduceMotion: reduceMotion)) {
                    proxy.scrollTo(request)
                }
                session.scrollRequest = nil
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if session.isFinding {
                FindBar(session: session)
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
        .safeAreaInset(edge: .bottom) {
            if session.saveFailed {
                SaveFailedBanner()
            }
        }
        .navigationTitle(session.map.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        #if os(macOS)
        .onDeleteCommand(perform: session.deleteSelection)
        #endif
        .toolbar { toolbar }
        .focusedSceneValue(\.editorSession, session)
        .onAppear { session.undoManager = undoManager }
        .onChange(of: undoManager) { _, manager in session.undoManager = manager }
        .onChange(of: session.focusRequest) { _, request in
            guard let request else { return }
            focusedNode = request
            session.focusRequest = nil
        }
        .onChange(of: focusedNode) { _, node in
            if let node { session.selection = node }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button(action: session.undo) {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!session.canUndo)
            Button(action: session.redo) {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .disabled(!session.canRedo)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: session.showFind) {
                Label("Find", systemImage: "magnifyingglass")
            }
            Button(action: session.addChild) {
                Label("Add Child", systemImage: "arrow.turn.down.right")
            }
            Button(action: session.addSibling) {
                Label("Add Sibling", systemImage: "plus")
            }
            Button(role: .destructive, action: session.deleteSelection) {
                Label("Delete", systemImage: "trash")
            }
            .disabled(!session.canDeleteSelection)
        }
    }
}

struct OutlineRow: View {
    let row: EditorSession.Row
    let isRoot: Bool
    let isFindMatch: Bool
    var focus: FocusState<NodeID?>.Binding
    let onRename: (String) -> Void
    let onToggle: () -> Void
    @State private var draft: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        row: EditorSession.Row,
        isRoot: Bool,
        isFindMatch: Bool,
        focus: FocusState<NodeID?>.Binding,
        onRename: @escaping (String) -> Void,
        onToggle: @escaping () -> Void
    ) {
        self.row = row
        self.isRoot = isRoot
        self.isFindMatch = isFindMatch
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
                .font(isRoot ? Typography.rootTopic : Typography.topic)
                .focused(focus, equals: row.id)
                .onSubmit(commit)
                .accessibilityLabel(isRoot ? Text("Central Topic") : Text("Topic, level \(row.depth + 1)"))
            if isFindMatch {
                // A shape as well as the color, so a match never shows by color alone.
                Image(systemName: "magnifyingglass")
                    .font(Typography.rowDetail)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Find Match")
            }
        }
        .padding(.leading, CGFloat(row.depth) * Spacing.outlineIndent)
        .listRowBackground(isFindMatch ? Palette.searchMatch : nil)
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

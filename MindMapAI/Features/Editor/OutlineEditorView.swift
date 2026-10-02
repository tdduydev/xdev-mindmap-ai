import MindMapDomain
import SwiftUI

/// The map as an indented outline: the way to use a map without the canvas,
/// for VoiceOver and the keyboard. Toolbar and menus come from `MapEditorView`.
struct OutlineEditorView: View {
    @Bindable var session: EditorSession
    @FocusState private var focusedNode: NodeID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isListFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            let rows = session.rows
            // Floating branches come after the main tree (FR-ORG-27).
            let split = rows.firstIndex { $0.node.isFloating(rootID: session.rootID) } ?? rows.endIndex
            List(selection: $session.selection) {
                ForEach(rows[..<split], content: row)
                if split < rows.endIndex {
                    Section("Floating Topics") {
                        ForEach(rows[split...], content: row)
                    }
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
        .focused($isListFocused)
        .accessibilityIdentifier(AccessibilityID.Outline.list)
        .overlay {
            if session.rows.isEmpty {
                ContentUnavailableView {
                    Label("Empty Map", systemImage: "point.3.connected.trianglepath.dotted")
                } actions: {
                    Button("Add Central Topic", action: session.addRoot)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier(AccessibilityID.Outline.addCentralTopic)
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
            reportKeyboardFocus()
        }
        .onChange(of: isListFocused) { reportKeyboardFocus() }
        .onAppear(perform: reportKeyboardFocus)
    }

    private func row(_ row: EditorSession.Row) -> some View {
        OutlineRow(
            row: row,
            isRoot: row.id == session.rootID,
            isFloating: row.node.isFloating(rootID: session.rootID),
            isFindMatch: session.findMatchSet.contains(row.id),
            focus: $focusedNode,
            onRename: { session.rename(row.id, to: $0) },
            onToggle: { session.toggleCollapsed(row.id) },
            onAttachOrDetach: attachOrDetach(row)
        )
    }

    /// The outline's way to the same commands as the Topic menu, for VoiceOver.
    private func attachOrDetach(_ row: EditorSession.Row) -> (() -> Void)? {
        if row.node.isFloating(rootID: session.rootID) { return { session.beginAttaching(row.id) } }
        guard row.node.parentID != nil else { return nil }
        return { session.selection = row.id; session.detachSelection() }
    }

    /// Delete Topic's bare-Delete shortcut follows this (see `EditorSession.deleteKeyDeletesTopic`).
    private func reportKeyboardFocus() {
        let focus: EditorSession.KeyboardFocus = focusedNode != nil ? .editingText : isListFocused ? .content : .elsewhere
        session.reportKeyboardFocus(focus, from: .outline)
    }
}

struct OutlineRow: View {
    let row: EditorSession.Row
    let isRoot: Bool
    var isFloating = false
    let isFindMatch: Bool
    var focus: FocusState<NodeID?>.Binding
    let onRename: (String) -> Void
    let onToggle: () -> Void
    var onAttachOrDetach: (() -> Void)?
    @State private var draft: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        row: EditorSession.Row,
        isRoot: Bool,
        isFloating: Bool = false,
        isFindMatch: Bool,
        focus: FocusState<NodeID?>.Binding,
        onRename: @escaping (String) -> Void,
        onToggle: @escaping () -> Void,
        onAttachOrDetach: (() -> Void)? = nil
    ) {
        self.row = row
        self.isRoot = isRoot
        self.isFloating = isFloating
        self.isFindMatch = isFindMatch
        self.focus = focus
        self.onRename = onRename
        self.onToggle = onToggle
        self.onAttachOrDetach = onAttachOrDetach
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
                .accessibilityLabel(accessibilityLabel)
                .accessibilityIdentifier(AccessibilityID.Outline.topic)
            if !row.tags.isEmpty {
                OutlineTagChips(tags: row.tags)
            }
            if let link = row.node.link, let url = link.url {
                OutlineLinkButton(link: link, url: url)
            }
            if row.topicImage != nil {
                Image(systemName: "photo")
                    .font(Typography.rowDetail)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            if row.node.hasNote {
                Image(systemName: "note.text")
                    .font(Typography.rowDetail)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("Note"))
            }
            if isFindMatch {
                // A shape as well as the color, so a match never shows by color alone.
                Image(systemName: "magnifyingglass")
                    .font(Typography.rowDetail)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Find Match")
            }
        }
        .padding(.leading, CGFloat(row.depth) * Spacing.outlineIndent)
        .modifier(TopicLinkAccessibility(link: row.node.link))
        .modifier(TopicImageAccessibility(image: row.topicImage))
        .accessibilityActions {
            if let onAttachOrDetach {
                Button(isFloating ? "Attach to Topic…" : "Detach Topic", action: onAttachOrDetach)
            }
        }
        .listRowBackground(isFindMatch ? Palette.searchMatchFill : nil)
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
        .accessibilityIdentifier(AccessibilityID.Outline.disclosure)
    }

    private var accessibilityLabel: Text {
        if isRoot { return Text("Central Topic") }
        return isFloating ? Text("Floating topic") : Text("Topic, level \(row.depth + 1)")
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

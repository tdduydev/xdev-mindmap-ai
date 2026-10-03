import MindMapDomain
import MindMapGraph
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
            // The outline's way to colour and symbol, on the rows the menu opened on.
            .contextMenu(forSelectionType: NodeID.self) { ids in
                let targets = session.inOutlineOrder(ids)
                TopicColorMenu(title: "Color", session: session, targets: targets)
                TopicSymbolMenu(title: "Symbol", session: session, targets: targets)
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
        #if os(macOS)
        // The table takes Return first; with a row selected and no field
        // editing, it opens that row's title, as Finder does (MM-89).
        .onKeyPress(.return) {
            guard focusedNode == nil, let selection = session.selection,
                  session.rows.contains(where: { $0.id == selection }) else { return .ignored }
            focusedNode = selection
            return .handled
        }
        #endif
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
        #if os(macOS)
        // The table spends the first click on a row selecting it and never
        // hands it to the field, so the title had no keyboard focus until a
        // second click (MM-89). A click edits at once; arrow keys only select.
        .onChange(of: session.selection) { _, selection in
            guard let selection, focusedNode != selection, NSApp.currentEvent?.isMouseClick == true else { return }
            focusedNode = selection
        }
        #endif
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
            onAttachOrDetach: attachOrDetach(row),
            onToggleDone: { session.toggleDone(row.id) }
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

#if os(macOS)
private extension NSEvent {
    var isMouseClick: Bool { type == .leftMouseDown || type == .leftMouseUp }
}
#endif

struct OutlineRow: View {
    let row: EditorSession.Row
    let isRoot: Bool
    var isFloating = false
    let isFindMatch: Bool
    var focus: FocusState<NodeID?>.Binding
    let onRename: (String) -> Void
    let onToggle: () -> Void
    var onAttachOrDetach: (() -> Void)?
    /// The task box (MM-35).
    var onToggleDone: (() -> Void)?
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
        onAttachOrDetach: (() -> Void)? = nil,
        onToggleDone: (() -> Void)? = nil
    ) {
        self.row = row
        self.isRoot = isRoot
        self.isFloating = isFloating
        self.isFindMatch = isFindMatch
        self.focus = focus
        self.onRename = onRename
        self.onToggle = onToggle
        self.onAttachOrDetach = onAttachOrDetach
        self.onToggleDone = onToggleDone
        _draft = State(initialValue: row.node.title)
    }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            disclosure
            if let state = row.node.taskState, let onToggleDone {
                OutlineTaskBox(isDone: state.isDone, action: onToggleDone)
            }
            if let color = ownColor {
                // The shape with the colour, so it never shows by colour alone.
                OutlineColorShape(color: color)
            }
            if let symbol = TopicSymbolCatalog.drawable(row.node.symbol) {
                TopicSymbolImage(symbol: symbol)
                    .font(isRoot ? Typography.Content.outlineRoot.font : Typography.Content.outlineTopic.font)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            TextField("Topic", text: $draft, prompt: Text("Untitled Topic"))
                .textFieldStyle(.plain)
                .font(isRoot ? Typography.Content.outlineRoot.font : Typography.Content.outlineTopic.font)
                .foregroundStyle(row.node.taskState?.isDone == true ? .secondary : .primary)
                .focused(focus, equals: row.id)
                .onSubmit(commit)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(Text(verbatim: taskValue))
                .modifier(TopicImageAccessibility(image: row.topicImage))
                .modifier(TopicStyleCustomContent(color: ownColor, symbol: TopicSymbolCatalog.drawable(row.node.symbol)))
                .accessibilityIdentifier(AccessibilityID.Outline.topic)
            if row.node.priority != nil || row.progress != nil || row.node.dueDate != nil {
                OutlineTaskDetails(node: row.node, progress: row.progress, today: .today())
            }
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
        .modifier(TaskDateCustomContent(due: row.node.dueDate))
        .accessibilityActions {
            if let state = row.node.taskState, let onToggleDone {
                Button(state.isDone ? "Mark as Not Done" : "Mark as Done", action: onToggleDone)
            }
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

    /// The central topic's colour is not drawn (`EditorSession.colorTargets`).
    private var ownColor: TopicColor? {
        guard !isRoot, let color = row.node.color, color.isKnown else { return nil }
        return color
    }

    private var accessibilityLabel: Text {
        if isRoot { return Text("Central Topic") }
        return isFloating ? Text("Floating topic") : Text("Topic, level \(row.depth + 1)")
    }

    /// "task, not done, priority High, overdue, 2 of 5 tasks done", as the canvas reads it.
    /// Starts with the title: a value set on a TextField replaces its text,
    /// so without it VoiceOver and UI tests saw an empty field (MM-87).
    private var taskValue: String {
        var parts: [String] = [draft]
        if let state = row.node.taskState {
            parts.append(state.isDone ? String(localized: "task, done") : String(localized: "task, not done"))
        }
        if let priority = row.node.priority { parts.append(String(localized: "priority \(priority.title)")) }
        if CalendarDay.isOverdue(row.node.dueDate, state: row.node.taskState, today: .today()) {
            parts.append(String(localized: "overdue"))
        }
        if let progress = row.progress {
            parts.append(String(localized: "\(progress.done) of \(progress.total) tasks done"))
        }
        return parts.joined(separator: ", ")
    }

    private func commit() {
        guard draft != row.node.title else { return }
        onRename(draft)
    }
}

/// A topic colour's shape in that colour, as the outline row's first mark.
private struct OutlineColorShape: View {
    let color: TopicColor
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Image(systemName: color.shapeSymbol)
            .font(.system(size: CanvasMetrics.topicColorShapeSize))
            .foregroundStyle(color.token[ColorVariant(colorScheme: colorScheme, contrast: contrast)].color)
            .accessibilityHidden(true)
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

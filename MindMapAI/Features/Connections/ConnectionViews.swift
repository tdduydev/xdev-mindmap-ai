import MindMapDomain
import MindMapGraph
import SwiftUI

struct ConnectionPickerPresenter: ViewModifier {
    @Bindable var session: EditorSession

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(
            get: { session.connectionSource != nil },
            set: { if !$0 { session.connectionSource = nil } }
        )) {
            if let source = session.connectionSource {
                ConnectionPickerSheet(session: session, sourceID: source)
            }
        }
    }
}

/// Picks the other end of a new connection by title or path. The keyboard,
/// outline and VoiceOver path to Add Connection, and the only one until the
/// canvas has a connect mode.
struct ConnectionPickerSheet: View {
    let session: EditorSession
    let sourceID: NodeID
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(filtered) { candidate in
                Button {
                    session.finishAddingConnection(to: candidate.id)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(Self.title(candidate.title))
                        if !candidate.path.isEmpty {
                            Text(candidate.path.joined(separator: " ▸ "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: Metrics.minimumHitTarget, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
            .searchable(text: $query, prompt: Text("Find a topic"))
            .navigationTitle("Add Connection")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: Metrics.connectionPickerSize.width, minHeight: Metrics.connectionPickerSize.height)
        #endif
    }

    private var filtered: [ConnectionCandidate] {
        let all = session.connectionCandidates(from: sourceID)
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return all }
        return all.filter { $0.title.localizedStandardContains(query) || $0.path.contains { $0.localizedStandardContains(query) } }
    }

    static func title(_ title: String) -> String {
        title.isEmpty ? String(localized: "Untitled Topic") : title
    }
}

/// The inspector's Connections section for the selected topic: each
/// connection's other end, label, line, arrows and colour.
struct ConnectionsInspectorSection: View {
    let session: EditorSession
    let nodeID: NodeID

    var body: some View {
        Section("Connections") {
            ForEach(session.connections(of: nodeID)) { connection in
                ConnectionInspectorRow(session: session, connection: connection)
            }
            Button("Add Connection…") { session.beginAddingConnection() }
                .disabled(!session.canAddConnection)
        }
    }
}

private struct ConnectionInspectorRow: View {
    let session: EditorSession
    let connection: ConnectionSummary
    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(session: EditorSession, connection: ConnectionSummary) {
        self.session = session
        self.connection = connection
        _draft = State(initialValue: connection.edge.label ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label {
                Text(connection.isOutgoing
                    ? "To \(ConnectionPickerSheet.title(connection.otherTitle))"
                    : "From \(ConnectionPickerSheet.title(connection.otherTitle))")
            } icon: {
                Image(systemName: connection.isOutgoing ? "arrow.up.right" : "arrow.down.left")
            }
            .accessibilityLabel(Text(connection.spokenDescription))
            // Typing stays a draft and becomes one "Edit Connection" step on commit.
            TextField("Label", text: $draft, prompt: Text("Add a label"))
                .focused($isFocused)
                .onSubmit(commit)
                .onChange(of: isFocused) { _, focused in if !focused { commit() } }
                .onChange(of: connection.edge.label) { _, label in if !isFocused { draft = label ?? "" } }
                .onDisappear(perform: commit)
            Picker("Line", selection: Binding(
                get: { connection.edge.resolvedLineStyle },
                set: { session.setConnectionLineStyle($0, for: connection.id) }
            )) {
                ForEach(EdgeLineStyle.choices, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Arrows", selection: Binding(
                get: { connection.edge.resolvedArrowHeads },
                set: { session.setConnectionArrowHeads($0, for: connection.id) }
            )) {
                ForEach(EdgeArrowHeads.choices, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Color", selection: Binding(
                get: { connection.edge.color },
                set: { session.setConnectionColor($0, for: connection.id) }
            )) {
                Text("Default").tag(TopicColor?.none)
                ForEach(TopicColor.all, id: \.self) { color in
                    Label(color.title, systemImage: color.shapeSymbol).tag(TopicColor?.some(color))
                }
            }
            HStack {
                Button("Reverse Connection") { session.reverseConnection(connection.id) }
                Spacer()
                Button("Remove Connection", role: .destructive) { session.removeConnection(connection.id) }
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private func commit() {
        let current = session.engine.state.edges[connection.id]?.label ?? ""
        guard draft.trimmingCharacters(in: .whitespacesAndNewlines) != current else { return }
        session.setConnectionLabel(draft, for: connection.id)
    }
}

/// "Connection to Budget, label: depends on" for each connection, read with
/// VoiceOver's "more content" so the topic's value stays short.
struct ConnectionAccessibility: ViewModifier {
    let descriptions: [String]

    func body(content: Content) -> some View {
        if descriptions.isEmpty {
            content
        } else {
            content.accessibilityCustomContent(Text("Connections"), Text(verbatim: descriptions.joined(separator: "; ")))
        }
    }
}

/// A connection's label edited where it is drawn (double-click the line).
/// Return or leaving the field commits one "Edit Connection" step; Esc
/// leaves the label as it was.
struct ConnectionLabelField: View {
    let model: CanvasModel
    let edgeID: EdgeID
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Label", text: $draft, prompt: Text("Add a label"))
            .textFieldStyle(.roundedBorder)
            .font(Typography.Content.badge.font)
            .frame(width: CanvasMetrics.connectionLabelMaxWidth)
            .focused($isFocused)
            .onAppear {
                draft = model.session.engine.state.edges[edgeID]?.label ?? ""
                isFocused = true
            }
            .onSubmit(finish)
            .onChange(of: isFocused) { _, focused in if !focused { finish() } }
            #if os(macOS)
            .onExitCommand { model.editingConnectionLabel = nil }
            #endif
            .onKeyPress(.escape) {
                model.editingConnectionLabel = nil
                return .handled
            }
            .accessibilityLabel(Text("Connection Label"))
    }

    private func finish() {
        guard model.editingConnectionLabel == edgeID else { return }
        model.editingConnectionLabel = nil
        model.session.setConnectionLabel(draft, for: edgeID)
    }
}

/// Format ▸ Connection for the connection selected on the canvas; disabled,
/// not hidden, when none is (docs/node-organization.md *Menus*).
struct ConnectionFormatMenu: View {
    let editor: EditorSession?
    let canvas: CanvasModel?

    var body: some View {
        let id = editor?.activeConnection
        let edge = id.flatMap { editor?.engine.state.edges[$0] }
        Menu("Connection") {
            Button("Edit Label") { canvas?.editingConnectionLabel = id }
                .disabled(canvas == nil)
            Menu("Line") {
                ForEach(EdgeLineStyle.choices, id: \.self) { style in
                    Toggle(style.title, isOn: Binding(
                        get: { edge?.resolvedLineStyle == style },
                        set: { _ in if let id { editor?.setConnectionLineStyle(style, for: id) } }
                    ))
                }
            }
            Menu("Arrows") {
                ForEach(EdgeArrowHeads.choices, id: \.self) { arrows in
                    Toggle(arrows.title, isOn: Binding(
                        get: { edge?.resolvedArrowHeads == arrows },
                        set: { _ in if let id { editor?.setConnectionArrowHeads(arrows, for: id) } }
                    ))
                }
            }
            Menu("Color") {
                Toggle("Default", isOn: Binding(
                    get: { edge != nil && edge?.color == nil },
                    set: { _ in if let id { editor?.setConnectionColor(nil, for: id) } }
                ))
                ForEach(TopicColor.all, id: \.self) { color in
                    Toggle(isOn: Binding(
                        get: { edge?.color == color },
                        set: { _ in if let id { editor?.setConnectionColor(color, for: id) } }
                    )) {
                        Label(color.title, systemImage: color.shapeSymbol)
                    }
                }
            }
            Divider()
            Button("Reverse Connection") { if let id { editor?.reverseConnection(id) } }
            Button("Remove Connection") { if let id { editor?.removeConnection(id) } }
        }
        .disabled(edge == nil)
    }
}

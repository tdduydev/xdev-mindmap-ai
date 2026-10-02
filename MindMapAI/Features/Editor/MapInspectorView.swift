import MindMapDomain
import MindMapGraph
import SwiftUI

/// The inspector beside an open map: the selected topic's note, tags and
/// details (FR-EDT-13), then the settings of the map itself. On iPhone `.inspector`
/// shows it as a sheet.
struct MapInspectorView: View {
    let session: EditorSession

    var body: some View {
        Form {
            if let node = session.selectedNode {
                Section("Note") {
                    // A new identity per topic, so a draft never carries over to
                    // the next selection; leaving commits it first.
                    TopicNoteEditor(session: session, nodeID: node.id, note: node.note)
                        .id(node.id)
                }
                Section("Link") {
                    TopicLinkInspectorField(session: session, nodeID: node.id, link: node.link)
                        .id(node.id)
                }
                Section {
                    TagField(session: session)
                } header: {
                    if session.selectedIDs.count > 1 {
                        Text("Tags of \(session.selectedIDs.count) Topics")
                    } else {
                        Text("Tags")
                    }
                }
                Section("Topic") {
                    TopicDetails(session: session, node: node)
                }
            } else {
                Section("Topic") {
                    Text("Select a topic to see its note.")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Map") {
                Picker("Theme", selection: themeBinding) {
                    ForEach(MindMapTheme.allCases) { theme in
                        HStack(spacing: Spacing.sm) {
                            Text(theme.title)
                            ThemeSwatch(theme: theme)
                        }
                        .tag(theme)
                    }
                }
                .pickerStyle(.inline)
                .accessibilityIdentifier(AccessibilityID.Inspector.theme)
            }
        }
        .formStyle(.grouped)
    }

    /// Every pick goes through the session, so it is one "Change Theme" undo step.
    private var themeBinding: Binding<MindMapTheme> {
        Binding(get: { session.map.theme }, set: { session.changeTheme(to: $0) })
    }
}

/// The note of one topic. Typing stays in a local draft and becomes one
/// "Edit Note" command when the field loses focus or the topic changes, so
/// undo takes back a whole edit rather than one keystroke at a time.
/// `TextEditor` brings the system's Writing Tools with it.
struct TopicNoteEditor: View {
    let session: EditorSession
    let nodeID: NodeID
    let note: String?
    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(session: EditorSession, nodeID: NodeID, note: String?) {
        self.session = session
        self.nodeID = nodeID
        self.note = note
        _draft = State(initialValue: note ?? "")
    }

    var body: some View {
        TextEditor(text: $draft)
            .font(Typography.Content.note.font)
            .lineSpacing(Typography.Content.note.lineSpacing)
            .writingToolsBehavior(.complete)
            .scrollContentBackground(.hidden)
            .frame(minHeight: Metrics.noteEditorMinHeight)
            .focused($isFocused)
            .overlay(alignment: .topLeading) {
                if draft.isEmpty, !isFocused {
                    Text("Add a note")
                        .font(Typography.Content.note.font)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, Spacing.xs)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel(Text("Note"))
            .accessibilityIdentifier(AccessibilityID.Inspector.note)
            // Undo, redo or an AI summary changed the note; show it unless the user is typing.
            .onChange(of: note) { _, note in
                if !isFocused { draft = note ?? "" }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
            .onChange(of: session.noteFocusRequest, initial: true) { _, request in
                guard request == nodeID else { return }
                isFocused = true
                session.noteFocusRequest = nil
            }
            .onDisappear(perform: commit)
    }

    private func commit() {
        // Compare with the graph, not the value this view was made with: undo may
        // have changed it, and an untouched blank note must not become an edit.
        let current = session.engine.state.node(nodeID)?.note ?? ""
        guard draft != current else { return }
        session.setNote(draft, for: nodeID)
    }
}

/// Read-only facts about the selected topic.
private struct TopicDetails: View {
    let session: EditorSession
    let node: MindNode

    var body: some View {
        let state = session.engine.state
        LabeledContent("Level") {
            if node.id == session.rootID {
                Text("Central Topic")
            } else {
                // Counted as the outline and the canvas read it to VoiceOver.
                Text(state.ancestors(of: node.id).count + 1, format: .number)
            }
        }
        LabeledContent("Subtopics") {
            Text(state.childIDs(of: node.id).count, format: .number)
        }
        LabeledContent("Added By") {
            Text(origin)
        }
        LabeledContent("Created") {
            Text(node.createdAt, format: .dateTime.day().month().year().hour().minute())
        }
        LabeledContent("Modified") {
            Text(node.updatedAt, format: .dateTime.day().month().year().hour().minute())
        }
    }

    private var origin: LocalizedStringKey {
        switch node.metadata.origin {
        case .user: "You"
        case .ai: "AI"
        case .imported: "Import"
        }
    }
}

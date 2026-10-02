import MindMapDomain
import SwiftUI

/// One open map, as a canvas or an outline. Both show the same session, so
/// switching keeps the selection (FR-CNV-12); the outline stays as the path
/// that needs no canvas (FR-EDT-16).
struct MapEditorView: View {
    @Bindable var session: EditorSession
    let canvas: CanvasModel
    @Bindable var assistant: AIAssistant
    @Bindable var voice: VoiceInput
    @Environment(\.undoManager) private var undoManager
    @State private var showsKeyboardShortcuts = false
    @Environment(FileTransfer.self) private var transfer: FileTransfer?

    var body: some View {
        Group {
            switch session.presentation {
            case .canvas:
                CanvasView(model: canvas)
            case .outline:
                OutlineEditorView(session: session)
            }
        }
        .safeAreaInset(edge: .top) {
            VStack(spacing: 0) {
                if session.isFinding {
                    FindBar(session: session)
                }
                AISuggestionBar(assistant: assistant)
            }
        }
        // The outline scrolls to a match itself; the canvas waits for the
        // layout, which a branch Find just opened may not have yet.
        .onChange(of: session.scrollRequest) { _, request in
            guard request != nil, session.presentation == .canvas else { return }
            canvas.revealSelection()
            session.scrollRequest = nil
        }
        .safeAreaInset(edge: .bottom) {
            if session.saveFailed {
                SaveFailedBanner()
            }
        }
        .sheet(item: $assistant.sheet, onDismiss: assistant.sheetDismissed) { sheet in
            AISheet(assistant: assistant, sheet: sheet)
        }
        .sheet(isPresented: $voice.isPresented, onDismiss: voice.sheetDismissed) {
            VoiceInputSheet(voice: voice)
        }
        .inspector(isPresented: $session.isInspectorPresented) {
            MapInspectorView(session: session)
        }
        // The window title on the Mac: the map, never the app name.
        .navigationTitle(session.displayTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        #if os(macOS)
        // Delete when the menu's Delete Topic shortcut is off: on a selected
        // suggestion, or where SwiftUI did not report the content's focus.
        .onDeleteCommand {
            // Delete on a selected suggestion discards it rather than a topic.
            if let suggestion = assistant.selectedSuggestion {
                assistant.discard(suggestion)
            } else {
                session.deleteSelection()
            }
        }
        #endif
        .toolbar { toolbar }
        .focusedSceneValue(\.editorSession, session)
        .focusedSceneValue(\.aiAssistant, assistant)
        .focusedSceneValue(\.keyboardShortcutsAction, KeyboardShortcutsAction { showsKeyboardShortcuts = true })
        .sheet(isPresented: $showsKeyboardShortcuts) { KeyboardShortcutsView() }
        .focusedSceneValue(\.voiceInput, voice)
        .onAppear { session.undoManager = undoManager }
        .onChange(of: undoManager) { _, manager in session.undoManager = manager }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            Picker("View As", selection: $session.presentation) {
                Label("Canvas", systemImage: "point.3.connected.trianglepath.dotted")
                    .tag(EditorPresentation.canvas)
                Label("Outline", systemImage: "list.bullet.indent")
                    .tag(EditorPresentation.outline)
            }
            .pickerStyle(.segmented)
            .help(Text("View As"))
            .accessibilityIdentifier(AccessibilityID.Editor.presentation)
        }
        // Design system: a multi-selection shows its count in the toolbar.
        ToolbarItem {
            if session.selectedIDs.count > 1 {
                Text("\(session.selectedIDs.count) topics selected")
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        ToolbarItemGroup {
            Button(action: session.undo) {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .accessibilityIdentifier(AccessibilityID.Editor.undo)
            .disabled(!session.canUndo)
            Button(action: session.redo) {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .accessibilityIdentifier(AccessibilityID.Editor.redo)
            .disabled(!session.canRedo)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: session.showFind) {
                Label("Find", systemImage: "magnifyingglass")
            }
            Button(action: session.addChild) {
                Label("Add Child Topic", systemImage: "arrow.turn.down.right")
            }
            .accessibilityIdentifier(AccessibilityID.Editor.addChild)
            Button(action: session.addSibling) {
                Label("Add Sibling Topic", systemImage: "plus")
            }
            .accessibilityIdentifier(AccessibilityID.Editor.addSibling)
            Button(role: .destructive, action: session.deleteSelection) {
                Label("Delete Topic", systemImage: "trash")
            }
            .accessibilityIdentifier(AccessibilityID.Editor.delete)
            .disabled(!session.canDeleteSelection)
            Button(action: voice.present) {
                Label("Add Topics by Voice", systemImage: "mic")
            }
            .help(Text("Add Topics by Voice"))
        }
        if assistant.service.showsEntryPoints {
            ToolbarItem(placement: .primaryAction) {
                AIToolbarMenu(assistant: assistant)
            }
        }
        if let transfer {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    transfer.beginExport(session)
                } label: {
                    Label("Export…", systemImage: "square.and.arrow.up")
                }
            }
        }
        // After the primary actions, so it sits at the trailing edge above the inspector.
        ToolbarItem(placement: .primaryAction) {
            Button {
                session.isInspectorPresented.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.trailing")
            }
            .help(session.isInspectorPresented ? Text("Hide Inspector") : Text("Show Inspector"))
        }
    }
}

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
            AISuggestionBar(assistant: assistant)
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
        .navigationTitle(session.map.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        #if os(macOS)
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
        }
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

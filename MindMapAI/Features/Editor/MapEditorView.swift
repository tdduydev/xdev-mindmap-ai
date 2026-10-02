import MindMapDomain
import SwiftUI

/// One open map, as a canvas or an outline. Both show the same session, so
/// switching keeps the selection (FR-CNV-12); the outline stays as the path
/// that needs no canvas (FR-EDT-16).
struct MapEditorView: View {
    @Bindable var session: EditorSession
    let canvas: CanvasModel
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
        .safeAreaInset(edge: .bottom) {
            if session.saveFailed {
                SaveFailedBanner()
            }
        }
        .inspector(isPresented: $session.isInspectorPresented) {
            MapInspectorView(session: session)
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

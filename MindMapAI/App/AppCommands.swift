import SwiftUI

/// What the menus can act on in the frontmost window.
extension FocusedValues {
    @Entry var editorSession: EditorSession?
    @Entry var newMapAction: NewMapAction?
    /// Set while the canvas shows; the zoom commands act on it.
    @Entry var canvasModel: CanvasModel?
}

struct NewMapAction {
    let perform: () -> Void
}

/// Every editor action is in the menu bar, with its shortcut, as the Mac
/// guidelines ask; on iPad the same commands fill the menu bar and the
/// keyboard shortcut overlay.
struct MapCommands: Commands {
    @FocusedValue(\.editorSession) private var editor
    @FocusedValue(\.newMapAction) private var newMap
    @FocusedValue(\.canvasModel) private var canvas
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // ⌘N makes a map, as New Document does in Mac apps; a new window moves to ⌥⌘N.
        CommandGroup(replacing: .newItem) {
            Button("New Mind Map") { newMap?.perform() }
                .keyboardShortcut("n")
                .disabled(newMap == nil)
            Button("New Window") { openWindow(id: MindMapAIApp.mainWindowID) }
                .keyboardShortcut("n", modifiers: [.command, .option])
        }

        // View menu: canvas or outline (⌘1, ⌘2, as Finder's View As), then zoom.
        CommandGroup(before: .toolbar) {
            Toggle("As Canvas", isOn: presentationBinding(.canvas))
                .keyboardShortcut("1")
                .disabled(editor == nil)
            Toggle("As Outline", isOn: presentationBinding(.outline))
                .keyboardShortcut("2")
                .disabled(editor == nil)
            Divider()
            Button("Zoom In") { canvas?.zoomIn() }
                .keyboardShortcut("+")
                .disabled(canvas?.canZoomIn != true)
            Button("Zoom Out") { canvas?.zoomOut() }
                .keyboardShortcut("-")
                .disabled(canvas?.canZoomOut != true)
            Button("Actual Size") { canvas?.zoomToActualSize() }
                .keyboardShortcut("0")
                .disabled(canvas == nil)
            Button("Zoom to Fit") { canvas?.zoomToFit() }
                .keyboardShortcut("0", modifiers: [.command, .option])
                .disabled(canvas?.canZoomToFit != true)
            Divider()
        }

        CommandMenu("Topic") {
            Button("Add Sibling Topic") { editor?.addSibling() }
                .keyboardShortcut(.return)
                .disabled(editor == nil)
            Button("Add Child Topic") { editor?.addChild() }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(editor == nil)
            // Return opens the title on the canvas; it is not a menu key equivalent
            // here, because a bare Return would then never reach text fields.
            Button("Rename Topic") { canvas?.beginEditingSelection() }
                .disabled(canvas == nil || editor?.canRenameSelection != true)
            Button("Duplicate Topic") { editor?.duplicateSelection() }
                .keyboardShortcut("d")
                .disabled(editor?.canDuplicateSelection != true)
            Divider()
            // ⇧Tab for Promote comes with the keyboard work in MM-5, where Tab is
            // kept for typing while a title is being edited.
            Button("Promote Topic") { editor?.promoteSelection() }
                .disabled(editor?.canPromoteSelection != true)
            Button("Demote Topic") { editor?.demoteSelection() }
                .disabled(editor?.canDemoteSelection != true)
            Divider()
            Button(editor?.selectionIsCollapsed == true ? "Expand Topic" : "Collapse Topic") {
                editor?.toggleSelectionCollapsed()
            }
            .disabled(editor?.canToggleSelection != true)
            Divider()
            Button("Delete Topic") { editor?.deleteSelection() }
                .disabled(editor?.canDeleteSelection != true)
        }

        CommandGroup(replacing: .help) {
            Link("MindMap AI Website", destination: AppLinks.website)
        }
    }

    private func presentationBinding(_ presentation: EditorPresentation) -> Binding<Bool> {
        Binding(
            get: { editor?.presentation == presentation },
            set: { if $0 { editor?.presentation = presentation } }
        )
    }
}

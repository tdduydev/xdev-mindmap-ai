import SwiftUI

/// What the menus can act on in the frontmost window.
extension FocusedValues {
    @Entry var editorSession: EditorSession?
    @Entry var newMapAction: NewMapAction?
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

        CommandMenu("Topic") {
            Button("Add Sibling Topic") { editor?.addSibling() }
                .keyboardShortcut(.return)
                .disabled(editor == nil)
            Button("Add Child Topic") { editor?.addChild() }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(editor == nil)
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
}

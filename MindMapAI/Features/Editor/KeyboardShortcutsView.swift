import SwiftUI

/// Help ▸ Keyboard Shortcuts: every shortcut of the editor in one list,
/// including the canvas keys that are not menu items (Return, Tab, Space,
/// arrows) and so do not show in the menu bar or the iPad's ⌘ overlay.
struct KeyboardShortcutsView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Shortcut {
        /// Key symbols, shown as written.
        var keys: String?
        /// Words for a key or a gesture, translated.
        var words: LocalizedStringKey?
        let action: LocalizedStringKey

        init(keys: String, action: LocalizedStringKey) {
            self.keys = keys
            self.action = action
        }

        init(words: LocalizedStringKey, action: LocalizedStringKey) {
            self.words = words
            self.action = action
        }

        var keysText: Text {
            if let keys { Text(verbatim: keys) } else { Text(words ?? "") }
        }
    }

    private struct ShortcutGroup {
        let title: LocalizedStringKey
        let shortcuts: [Shortcut]
    }

    private let groups: [ShortcutGroup] = [
        ShortcutGroup(title: "On the Canvas", shortcuts: [
            Shortcut(keys: "↩", action: "Add Sibling Topic"),
            Shortcut(keys: "⇥", action: "Add Child Topic"),
            Shortcut(keys: "⇧⇥", action: "Promote Topic"),
            Shortcut(words: "Space", action: "Rename Topic"),
            Shortcut(keys: "↑ ↓ ← →", action: "Select the next topic"),
            Shortcut(keys: "⇧ ↑ ↓ ← →", action: "Add the next topic to the selection"),
            Shortcut(keys: "⎋", action: "Keep only the first selected topic"),
        ]),
        ShortcutGroup(title: "Topics", shortcuts: [
            Shortcut(keys: "⌘↩", action: "Add Sibling Topic"),
            Shortcut(keys: "⇧⌘↩", action: "Add Child Topic"),
            Shortcut(keys: "⇧⌘E", action: "Edit Note"),
            Shortcut(keys: "⌘D", action: "Duplicate Topic"),
            Shortcut(keys: "⌫", action: "Delete Topic"),
        ]),
        ShortcutGroup(title: "Edit", shortcuts: [
            Shortcut(keys: "⌘Z", action: "Undo"),
            Shortcut(keys: "⇧⌘Z", action: "Redo"),
            Shortcut(keys: "⌘X", action: "Cut"),
            Shortcut(keys: "⌘C", action: "Copy"),
            Shortcut(keys: "⌘V", action: "Paste"),
            Shortcut(keys: "⌘A", action: "Select All"),
        ]),
        ShortcutGroup(title: "Selection and Moving", shortcuts: Self.pointerShortcuts),
        ShortcutGroup(title: "View", shortcuts: [
            Shortcut(keys: "⌘1", action: "As Canvas"),
            Shortcut(keys: "⌘2", action: "As Outline"),
            Shortcut(keys: "⌘+", action: "Zoom In"),
            Shortcut(keys: "⌘−", action: "Zoom Out"),
            Shortcut(keys: "⌘0", action: "Actual Size"),
            Shortcut(keys: "⌥⌘0", action: "Zoom to Fit"),
        ]),
    ]

    #if os(macOS)
    private static let pointerShortcuts = [
        Shortcut(words: "⌘-click", action: "Add or remove a topic"),
        Shortcut(words: "⇧-click", action: "Add a topic"),
        Shortcut(words: "⌘-drag", action: "Select topics in a rectangle"),
        Shortcut(words: "⇧-drag", action: "Add topics in a rectangle"),
        Shortcut(words: "Drag a topic", action: "Move it, or drop it on another topic"),
    ]
    #else
    // Gestures on iOS read no modifier keys; touch has its own ways.
    private static let pointerShortcuts = [
        Shortcut(words: "Hold, then drag", action: "Select topics in a rectangle"),
        Shortcut(words: "Drag a topic", action: "Move it, or drop it on another topic"),
    ]
    #endif

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups.indices, id: \.self) { groupIndex in
                    let group = groups[groupIndex]
                    Section(group.title) {
                        ForEach(group.shortcuts.indices, id: \.self) { index in
                            let shortcut = group.shortcuts[index]
                            LabeledContent {
                                shortcut.keysText
                                    .monospaced()
                            } label: {
                                Text(shortcut.action)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Keyboard Shortcuts")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: Metrics.shortcutsSheetSize.width, minHeight: Metrics.shortcutsSheetSize.height)
        #endif
    }
}

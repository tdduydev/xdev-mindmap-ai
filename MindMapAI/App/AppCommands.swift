import MindMapAICore
import MindMapDomain
import SwiftUI

/// What the menus can act on in the frontmost window.
extension FocusedValues {
    @Entry var editorSession: EditorSession?
    @Entry var newMapAction: NewMapAction?
    /// Set while the canvas shows; the zoom commands act on it.
    @Entry var canvasModel: CanvasModel?
    /// The AI side of the frontmost map, for the AI menu.
    @Entry var aiAssistant: AIAssistant?
    @Entry var newMapWithAIAction: NewMapAction?
    @Entry var keyboardShortcutsAction: KeyboardShortcutsAction?
}

struct NewMapAction {
    let perform: () -> Void
}

struct KeyboardShortcutsAction {
    let perform: () -> Void
}

/// Every editor action is in the menu bar, with its shortcut, as the Mac
/// guidelines ask; on iPad the same commands fill the menu bar and the
/// keyboard shortcut overlay.
struct MapCommands: Commands {
    let ai: AIService
    @FocusedValue(\.editorSession) private var editor
    @FocusedValue(\.aiAssistant) private var assistant
    @FocusedValue(\.newMapWithAIAction) private var newMapWithAI
    @FocusedValue(\.newMapAction) private var newMap
    @FocusedValue(\.canvasModel) private var canvas
    @FocusedValue(\.keyboardShortcutsAction) private var keyboardShortcuts
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
            Picker("Theme", selection: themeBinding) {
                ForEach(MindMapTheme.allCases) { theme in
                    Text(theme.title).tag(theme)
                }
            }
            .disabled(editor == nil)
            Divider()
        }

        CommandMenu("Topic") {
            Button("Add Sibling Topic") { editor?.addSibling() }
                .keyboardShortcut(.return)
                .disabled(editor == nil)
            Button("Add Child Topic") { editor?.addChild() }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(editor == nil)
            // Space opens the title on the canvas (Return adds a sibling there,
            // FR-KBD-01). Neither is a menu key equivalent: a bare key in the menu
            // would never reach text fields. Help ▸ Keyboard Shortcuts lists them.
            Button("Rename Topic") { canvas?.beginEditingSelection() }
                .disabled(canvas == nil || editor?.canRenameSelection != true)
            Button("Duplicate Topic") { editor?.duplicateSelection() }
                .keyboardShortcut("d")
                .disabled(editor?.canDuplicateSelection != true)
            Divider()
            // ⇧Tab promotes on the canvas, for the same reason as Space above.
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

        // Hidden, like every AI entry point, where the device can never run
        // Apple Intelligence (FR-AI-02); otherwise disabled with one line of why.
        if ai.showsEntryPoints {
            CommandMenu("AI") { aiMenu }
        }

        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts") { keyboardShortcuts?.perform() }
                .disabled(keyboardShortcuts == nil)
            Link("MindMap AI Help", destination: AppLinks.support)
            Link("MindMap AI Website", destination: AppLinks.website)
            Link("Privacy Policy", destination: AppLinks.privacyPolicy)
        }
    }

    @ViewBuilder
    private var aiMenu: some View {
        if let note = AIAvailabilityText.explanation(for: ai.modelState) {
            Text(note)
        }
        Button("New Map with AI…") { newMapWithAI?.perform() }
            .disabled(newMapWithAI == nil || !ai.modelState.isReady)
        Button("Generate Map…") { assistant?.requestGenerateMap() }
            .keyboardShortcut("g", modifiers: [.command, .control])
            .disabled(assistant?.canRun(.generateMap) != true)
        Divider()
        Button("Suggest Subtopics") { assistant?.expand() }
            .keyboardShortcut("e", modifiers: [.command, .control])
            .disabled(assistant?.canRun(.expandTopic) != true)
        Button("Brainstorm Ideas…") { assistant?.requestBrainstorm() }
            .keyboardShortcut("b", modifiers: [.command, .control])
            .disabled(assistant?.canRun(.brainstorm) != true)
        Menu("Rewrite Topic") {
            ForEach(RewriteStyle.allCases, id: \.self) { style in
                Button(style.title) { assistant?.rewrite(style: style) }
            }
        }
        .disabled(assistant?.canRun(.rewrite) != true)
        Button("Summarize Branch") { assistant?.summarize() }
            .keyboardShortcut("u", modifiers: [.command, .control])
            .disabled(assistant?.canRun(.summarize) != true)
        Button("Find Missing Topics") { assistant?.findMissingTopics() }
            .keyboardShortcut("m", modifiers: [.command, .control])
            .disabled(assistant?.canRun(.findMissingTopics) != true)
        Divider()
        Button("Accept All Suggestions") { assistant?.acceptAll() }
            .keyboardShortcut(.return, modifiers: [.command, .control])
            .disabled(assistant?.canAcceptSuggestions != true)
        Button("Discard Suggestions") { assistant?.discardAll() }
            .keyboardShortcut(.delete, modifiers: [.command, .control])
            .disabled(assistant?.hasSuggestions != true)
        // ⌘. is the Mac's key for stopping an operation.
        Button("Cancel AI Request") { assistant?.cancel() }
            .keyboardShortcut(".")
            .disabled(assistant?.isWorking != true)
    }

    private var themeBinding: Binding<MindMapTheme> {
        Binding(
            get: { editor?.map.theme ?? .standard },
            set: { editor?.changeTheme(to: $0) }
        )
    }

    private func presentationBinding(_ presentation: EditorPresentation) -> Binding<Bool> {
        Binding(
            get: { editor?.presentation == presentation },
            set: { if $0 { editor?.presentation = presentation } }
        )
    }
}

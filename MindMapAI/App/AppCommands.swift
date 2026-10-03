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
    /// Ask About This Map in the frontmost map window.
    @Entry var mapChat: MapChat?
    @Entry var newMapWithAIAction: NewMapAction?
    @Entry var keyboardShortcutsAction: KeyboardShortcutsAction?
    /// Voice input for the frontmost map (FR-AI-21).
    @Entry var voiceInput: VoiceInput?
    /// The chat's microphone in the frontmost map window (MM-80).
    @Entry var chatDictation: ChatDictation?
    /// The map selected in the library, to show in a window of its own.
    @Entry var openInNewWindowAction: OpenInNewWindowAction?
    /// The map selected in the focused library list, for File ▸ Delete Map and the Recently Deleted commands.
    @Entry var libraryMapActions: LibraryMapActions?
}

struct NewMapAction {
    let perform: () -> Void
}

struct KeyboardShortcutsAction {
    let perform: () -> Void
}

struct OpenInNewWindowAction {
    let perform: () -> Void
}

/// Nil members are commands that do not apply to the selection, shown disabled.
struct LibraryMapActions {
    var delete: (() -> Void)?
    var restore: (() -> Void)?
    var deletePermanently: (() -> Void)?
}

/// Every editor action is in the menu bar, with its shortcut, as the Mac
/// guidelines ask; on iPad the same commands fill the menu bar and the
/// keyboard shortcut overlay.
struct MapCommands: Commands {
    let ai: AIService
    @FocusedValue(\.editorSession) private var editor
    @FocusedValue(\.aiAssistant) private var assistant
    @FocusedValue(\.mapChat) private var chat
    @FocusedValue(\.newMapWithAIAction) private var newMapWithAI
    @FocusedValue(\.newMapAction) private var newMap
    @FocusedValue(\.canvasModel) private var canvas
    @FocusedValue(\.keyboardShortcutsAction) private var keyboardShortcuts
    @FocusedValue(\.voiceInput) private var voice
    @FocusedValue(\.chatDictation) private var dictation
    @FocusedValue(\.openInNewWindowAction) private var openInNewWindow
    @FocusedValue(\.libraryMapActions) private var libraryMap
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL

    var body: some Commands {
        // ⌘N makes a map, as New Document does in Mac apps; a new window moves to ⌥⌘N.
        CommandGroup(replacing: .newItem) {
            Button("New Mind Map") { newMap?.perform() }
                .keyboardShortcut("n")
                .disabled(newMap == nil)
            Button("New Window") { openWindow(id: MindMapAIApp.mainWindowID) }
                .keyboardShortcut("n", modifiers: [.command, .option])
            // One window per map (FR-LIB-10); a map already in a window brings that window forward.
            Button("Open in New Window") { openInNewWindow?.perform() }
                .keyboardShortcut("o", modifiers: [.command, .option])
                .disabled(openInNewWindow == nil)
            Divider()
            // ⌘Delete and ⌥⌘Delete as Finder's Move to Trash and Delete
            // Immediately. Set only while they apply, which is only while the
            // library list has focus: a menu key equivalent is matched before
            // a text field sees the key, and ⌘Delete edits text there.
            Button("Delete Map") { libraryMap?.delete?() }
                .keyboardShortcut(libraryMap?.delete == nil ? nil : KeyboardShortcut(.delete))
                .disabled(libraryMap?.delete == nil)
            Button("Restore Map") { libraryMap?.restore?() }
                .disabled(libraryMap?.restore == nil)
            Button("Delete Map Permanently…") { libraryMap?.deletePermanently?() }
                .keyboardShortcut(libraryMap?.deletePermanently == nil ? nil : KeyboardShortcut(.delete, modifiers: [.command, .option]))
                .disabled(libraryMap?.deletePermanently == nil)
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
                    ProChoiceLabel(title: theme.title, isLocked: theme.requiresPro && !ai.entitlements.allows(.extraThemes))
                        .tag(theme)
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
            // ⌥⌘↩ next to the other Add keys (MM-58); free in the standard menus.
            Button("Add Floating Topic") {
                if let canvas { canvas.addFloatingTopic() } else { editor?.addFloatingTopic() }
            }
            .keyboardShortcut(.return, modifiers: [.command, .option])
            .disabled(editor?.canAddFloatingTopic != true)
            // Space opens the title on the canvas (Return adds a sibling there,
            // FR-KBD-01). Neither is a menu key equivalent: a bare key in the menu
            // would never reach text fields. Help ▸ Keyboard Shortcuts lists them.
            Button("Rename Topic") { canvas?.beginEditingSelection() }
                .disabled(canvas == nil || editor?.canRenameSelection != true)
            // ⇧⌘E: no standard Mac meaning, and ⌥⌘N is already New Window.
            Button("Edit Note") { editor?.editSelectionNote() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(editor?.canEditSelectionNote != true)
            // ⌘K is Add Link in Mail, Pages and most editors; ⌘L stays for Connections (decided 2026-10-02).
            Button(editor?.selectionHasLink == true ? "Edit Link…" : "Add Link…") { editor?.beginEditingSelectionLink() }
                .keyboardShortcut("k")
                .disabled(editor?.canEditSelectionLink != true)
            Button("Open Link") {
                if let url = editor?.selectionLinkURL { openURL(url) }
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(editor?.selectionLinkURL == nil)
            Button("Remove Link") {
                if let editor, let id = editor.selection { editor.removeLink(from: id) }
            }
            .disabled(editor?.selectionHasLink != true)
            // ⌘L as in MindNode (product owner, 2026-10-02); with two topics
            // selected it connects them without the picker.
            Button("Add Connection…") { editor?.beginAddingConnection() }
                .keyboardShortcut("l")
                .disabled(editor?.canAddConnection != true)
            Button(editor?.selectedImage == nil ? "Add Image…" : "Replace Image…") {
                editor?.imagePickerTarget = editor?.selection
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(editor?.canEditSelectionImage != true)
            Button("Remove Image") {
                if let editor, let id = editor.selection { Task { await editor.removeImage(from: id) } }
            }
            .disabled(editor?.selectedImage == nil)
            // ⌥⇧⌘↩ beside the other Add keys (MM-58); free in the standard menus.
            Button(editor?.selectionHasCallout == true ? "Edit Callout" : "Add Callout") {
                editor?.beginEditingSelectionCallout()
            }
            .keyboardShortcut(.return, modifiers: [.command, .option, .shift])
            .disabled(editor?.canEditSelectionCallout != true)
            Button("Remove Callout") {
                if let editor, let id = editor.selection { editor.removeCallout(from: id) }
            }
            .disabled(editor?.selectionHasCallout != true)
            // ⇧⌘T and ⌥⇧⌘T: free in the menus; this app has no Fonts panel (⌘T).
            Button("Add Tag…") { editor?.beginAddingTag() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(editor?.canTagSelection != true)
            if let editor {
                TagsMenu(session: editor, onAddTag: editor.beginAddingTag)
            } else {
                Menu("Tags") {}
                    .disabled(true)
            }
            Button("Manage Tags…") { editor?.isManagingTags = true }
                .keyboardShortcut("t", modifiers: [.command, .option, .shift])
                .disabled(editor == nil)
            Divider()
            // ⇧⌘K, ⌥⌘K, ⌥⌘1–3 and ⌥⇧⌘K (MM-30): free in the standard menus; ⌘K stays Add Link.
            Button(editor?.areAllTasks() == true ? "Remove Task" : "Make Task") { editor?.toggleTask() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(editor?.canEditSelectionTask != true)
            Button(editor?.areTasksDone() == true ? "Mark as Not Done" : "Mark as Done") { editor?.toggleDone() }
                .keyboardShortcut("k", modifiers: [.command, .option])
                .disabled(editor?.hasTask() != true)
            if let editor {
                PriorityPicker(session: editor, showsShortcuts: true)
            } else {
                Menu("Priority") {}
                    .disabled(true)
            }
            Button("Set Task Dates…") { editor?.beginSettingTaskDates() }
                .keyboardShortcut("k", modifiers: [.command, .option, .shift])
                .disabled(editor?.canEditSelectionTask != true)
            Divider()
            // ⌥⌘B (MM-30): ⌘G stays Find Next. Acts on a selected boundary first.
            Button(editor?.boundaryToRemove != nil ? "Remove Boundary" : "Add Boundary") { editor?.toggleBoundary() }
                .keyboardShortcut("b", modifiers: [.command, .option])
                .disabled(editor?.boundaryToRemove == nil && editor?.canAddBoundary != true)
            Button("Rename Boundary") {
                if let id = editor?.activeBoundary { canvas?.editingBoundaryTitle = id }
            }
            .disabled(canvas == nil || editor?.activeBoundary == nil)
            // ⌥⌘] (MM-58): the bracket's shape. Acts on a selected summary topic first.
            Button(editor?.summaryToRemove != nil ? "Remove Summary" : "Add Summary") { editor?.toggleSummary() }
                .keyboardShortcut("]", modifiers: [.command, .option])
                .disabled(editor?.summaryToRemove == nil && editor?.canAddSummary != true)
            Divider()
            Button("Duplicate Topic") { editor?.duplicateSelection() }
                .keyboardShortcut("d")
                .disabled(editor?.canDuplicateSelection != true)
            Button("Add Topics by Voice…") { voice?.present() }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(voice == nil || voice?.isPresented == true)
            Divider()
            // ⇧Tab promotes on the canvas, for the same reason as Space above.
            Button("Detach Topic") { editor?.detachSelection() }
                .disabled(editor?.canDetachSelection != true)
            Button("Attach to Topic…") {
                if let id = editor?.selection { editor?.beginAttaching(id) }
            }
            .disabled(editor?.canAttachSelection != true)
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
                .keyboardShortcut(deleteTopicShortcut)
                .disabled(editor?.canDeleteSelection != true)
        }

        CommandMenu("Format") {
            if let editor {
                TopicColorMenu(title: "Topic Color", session: editor)
                TopicSymbolMenu(title: "Topic Symbol", session: editor)
            } else {
                Menu("Topic Color") {}
                    .disabled(true)
                Menu("Topic Symbol") {}
                    .disabled(true)
            }
            Divider()
            Menu("Image Size") {
                Button("Small") {
                    if let editor, let image = editor.selectedImage {
                        editor.setImageSize(CanvasMetrics.imageWidthSmall, for: image.id)
                    }
                }
                Button("Medium") {
                    if let editor, let image = editor.selectedImage {
                        editor.setImageSize(CanvasMetrics.imageWidthMedium, for: image.id)
                    }
                }
                Button("Large") {
                    if let editor, let image = editor.selectedImage {
                        editor.setImageSize(CanvasMetrics.imageWidthLarge, for: image.id)
                    }
                }
            }
            .disabled(editor?.selectedImage == nil)
            ConnectionFormatMenu(editor: editor, canvas: canvas)
            BoundaryFormatMenu(editor: editor)
        }

        // Edit ▸ Find, as in other Mac apps; the window has no Find menu of its own.
        CommandGroup(after: .pasteboard) {
            Divider()
            Menu("Find") {
                Button("Find…") { editor?.showFind() }
                    .keyboardShortcut("f")
                    .disabled(editor == nil)
                Button("Find Next") { editor?.findNext() }
                    .keyboardShortcut("g")
                    .disabled(editor?.hasFindMatches != true)
                Button("Find Previous") { editor?.findPrevious() }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(editor?.hasFindMatches != true)
            }
        }

        // Hidden, like every AI entry point, where the device can never run
        // Apple Intelligence (FR-AI-02); otherwise disabled with one line of
        // why, including when Use AI Features is off.
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
        if let note = ai.unavailableReason {
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
        Button("Suggest Tags") { assistant?.suggestTags() }
            .keyboardShortcut("t", modifiers: [.command, .control])
            .disabled(assistant?.canRun(.suggestTags) != true)
        // ⌃⌘O and ⌃⌘Y (MM-30), beside the other AI keys.
        Button("Suggest Groups") { assistant?.suggestGroups() }
            .keyboardShortcut("o", modifiers: [.command, .control])
            .disabled(assistant?.canRun(.suggestGroups) != true)
        Button("Summarize Boundary") { assistant?.summarizeBoundary() }
            .keyboardShortcut("y", modifiers: [.command, .control])
            .disabled(assistant?.canRun(.summarizeBoundary) != true)
        Divider()
        // ⌃⌘A: free beside the other AI keys (⌃⌘G, E, B, U, M, T) and not a
        // standard macOS shortcut; approved 2026-10-02.
        Button("Ask About This Map…") { chat?.present() }
            .keyboardShortcut("a", modifiers: [.command, .control])
            .disabled(chat?.showsEntryPoints != true)
        // The chat's microphone (MM-80). No key yet: none has been approved.
        Button {
            chat?.present()
            dictation?.toggle()
        } label: {
            dictation?.isListening == true ? Text("Stop Asking by Voice") : Text("Ask by Voice")
        }
        .disabled(dictation?.canToggle != true)
        Button("Clear Chat") { chat?.requestClear() }
            .disabled(chat?.canClear != true)
        // The answer buttons on the last answer (MM-79). No keys yet: none
        // has been approved, and ⌘C would steal Copy from the canvas.
        Button("Copy Answer") { chat?.copyLastAnswer() }
            .disabled(chat?.canCopyLastAnswer != true)
        Button("Add Answer to Note") { chat?.addLastAnswerToNote() }
            .disabled(chat?.canAddLastAnswerToNote != true)
        Button("Ask Again") { chat?.askLastQuestionAgain() }
            .disabled(chat?.canAskLastQuestionAgain != true)
        Divider()
        Button("Accept All Suggestions") { assistant?.acceptAll() }
            .keyboardShortcut(.return, modifiers: [.command, .control])
            .disabled(assistant?.canAcceptSuggestions != true)
        Button("Discard Suggestions") { assistant?.discardAll() }
            .keyboardShortcut(.delete, modifiers: [.command, .control])
            .disabled(assistant?.hasSuggestions != true)
        // ⌘. is the Mac's key for stopping an operation.
        // It stops a chat answer too, so the chat needs no key of its own.
        Button("Cancel AI Request") {
            assistant?.cancel()
            chat?.stop()
        }
        .keyboardShortcut(".")
        .disabled(assistant?.isWorking != true && chat?.isAnswering != true)
    }

    /// The bare Delete key comes and goes with focus, so it stays with text
    /// fields and with a selected suggestion (see `EditorSession.deleteKeyDeletesTopic`).
    private var deleteTopicShortcut: KeyboardShortcut? {
        guard editor?.deleteKeyDeletesTopic == true, assistant?.holdsDeleteKey != true else { return nil }
        return KeyboardShortcut(.delete, modifiers: [])
    }

    private var themeBinding: Binding<MindMapTheme> {
        Binding(
            get: { editor?.map.theme ?? .standard },
            set: { editor?.chooseTheme($0, entitlements: ai.entitlements) }
        )
    }

    private func presentationBinding(_ presentation: EditorPresentation) -> Binding<Bool> {
        Binding(
            get: { editor?.presentation == presentation },
            set: { if $0 { editor?.presentation = presentation } }
        )
    }
}

import MindMapDomain
import MindMapSearch
import SwiftUI
import TipKit

/// One open map, as a canvas or an outline. Both show the same session, so
/// switching keeps the selection (FR-CNV-12); the outline stays as the path
/// that needs no canvas (FR-EDT-16).
struct MapEditorView: View {
    @Bindable var session: EditorSession
    let canvas: CanvasModel
    @Bindable var assistant: AIAssistant
    @Bindable var chat: MapChat
    @Bindable var voice: VoiceInput
    let dictation: ChatDictation
    @Environment(\.undoManager) private var undoManager
    @AppStorage("onboarding.introductionFinished", store: AppDefaults.store) private var introductionFinished = false
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
                if session.isFilterBarShown {
                    FilterBar(session: session)
                }
                if session.focusID != nil {
                    FocusBreadcrumb(session: session)
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
        // The topic inspector and the chat share the trailing panel (a sheet
        // on iPhone); showing one hides the other.
        .inspector(isPresented: trailingPanelBinding) {
            if chat.isPresented {
                ChatPanel(chat: chat, dictation: dictation)
            } else {
                MapInspectorView(session: session)
            }
        }
        .onChange(of: session.isInspectorPresented) { _, isPresented in
            if isPresented { chat.isPresented = false }
        }
        .onChange(of: chat.isPresented) { _, isPresented in
            if isPresented { session.isInspectorPresented = false }
        }
        .sheet(isPresented: linkSheetBinding) {
            if let target = session.linkEditorTarget {
                TopicLinkSheet(session: session, nodeID: target)
            }
        }
        .modifier(AttachFloatingTopicSheetPresenter(session: session))
        .modifier(ConnectionPickerPresenter(session: session))
        .modifier(TopicImagePicker(session: session))
        .modifier(TopicSymbolPickerPresenter(session: session))
        .sheet(isPresented: $session.isManagingTags) {
            TagManagerView(session: session)
        }
        // Here rather than in the inspector, so View ▸ Theme can open it with the inspector closed.
        .proChoicePaywall($session.pendingThemeChoice)
        // A tag typed in the inspector that cannot be a name; Manage Tags shows its own.
        .alert(
            Text("Couldn’t Change the Tag"),
            isPresented: Binding(
                get: { session.tagFailure != nil && !session.isManagingTags },
                set: { if !$0 { session.tagFailure = nil } }
            ),
            presenting: session.tagFailure
        ) { _ in
            Button("OK") { session.tagFailure = nil }
        } message: { failure in
            Text(failure.message)
        }
        // Shared tag changes from other windows; this window's own arrive too and change nothing.
        .task { await session.observeStore() }
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
        .focusedSceneValue(\.mapChat, chat)
        .focusedSceneValue(\.keyboardShortcutsAction, KeyboardShortcutsAction { showsKeyboardShortcuts = true })
        .sheet(isPresented: $showsKeyboardShortcuts) { KeyboardShortcutsView() }
        .focusedSceneValue(\.voiceInput, voice)
        .focusedSceneValue(\.chatDictation, dictation)
        .onAppear { session.undoManager = undoManager }
        .onChange(of: undoManager) { _, manager in session.undoManager = manager }
    }

    private var linkSheetBinding: Binding<Bool> {
        Binding(
            get: { session.linkEditorTarget != nil },
            set: { if !$0 { session.linkEditorTarget = nil } }
        )
    }

    private var trailingPanelBinding: Binding<Bool> {
        Binding(
            get: { session.isInspectorPresented || chat.isPresented },
            set: { isPresented in
                if !isPresented {
                    session.isInspectorPresented = false
                    chat.isPresented = false
                } else if !chat.isPresented {
                    session.isInspectorPresented = true
                }
            }
        )
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
        // While a filter is on, even with the bar closed (MM-36).
        ToolbarItem {
            if session.filter.isActive {
                FilterChip(session: session)
            }
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
            Button {
                EditorTips.find.invalidate(reason: .actionPerformed)
                session.showFind()
            } label: {
                Label("Find", systemImage: "magnifyingglass")
            }
            .accessibilityIdentifier(AccessibilityID.Editor.find)
            .popoverTip(introductionFinished && !UITestMode.isActive ? EditorTips.find : nil)
            // The only way to the filter on iPhone, which has no menu bar.
            Button(action: session.toggleFilterBar) {
                Label("Filter", systemImage: session.filter.isActive
                    ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            .help(session.isFilterBarShown ? Text("Hide Filter Bar") : Text("Show Filter Bar"))
            Button {
                EditorTips.addTopic.invalidate(reason: .actionPerformed)
                session.addChild()
            } label: {
                Label("Add Child Topic", systemImage: "arrow.turn.down.right")
            }
            .accessibilityIdentifier(AccessibilityID.Editor.addChild)
            .popoverTip(introductionFinished && !UITestMode.isActive ? EditorTips.addTopic : nil)
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
            .accessibilityIdentifier(AccessibilityID.Editor.voice)
        }
        if assistant.service.showsControls {
            ToolbarItem(placement: .primaryAction) {
                AIToolbarMenu(assistant: assistant)
                    .accessibilityIdentifier(AccessibilityID.Editor.ai)
                    .popoverTip(introductionFinished && !UITestMode.isActive ? EditorTips.ai : nil)
            }
        }
        if chat.showsEntryPoints {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    EditorTips.chat.invalidate(reason: .actionPerformed)
                    if chat.isPresented { chat.isPresented = false } else { chat.present() }
                } label: {
                    Label("Ask About This Map", systemImage: "bubble.left.and.text.bubble.right")
                }
                .help(chat.isPresented ? Text("Hide Chat") : Text("Ask About This Map"))
                .accessibilityIdentifier(AccessibilityID.Chat.toolbar)
                .popoverTip(introductionFinished && !UITestMode.isActive ? EditorTips.chat : nil)
            }
        }
        if let transfer {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    transfer.beginExport(session)
                } label: {
                    Label("Export…", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier(AccessibilityID.Editor.export)
            }
            #if os(iOS)
            // The Mac and an iPad with a keyboard reach it in File ▸ Import into Map…;
            // an iPhone has no menu bar, and the library's Import… is a screen away.
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    transfer.beginImport(.openMap(session))
                } label: {
                    Label("Import into Map…", systemImage: "square.and.arrow.down")
                }
                .accessibilityIdentifier(AccessibilityID.Editor.importIntoMap)
            }
            #endif
        }
        // After the primary actions, so it sits at the trailing edge above the inspector.
        ToolbarItem(placement: .primaryAction) {
            Button {
                session.isInspectorPresented.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.trailing")
            }
            .help(session.isInspectorPresented ? Text("Hide Inspector") : Text("Show Inspector"))
            .accessibilityIdentifier(AccessibilityID.Editor.inspector)
        }
    }
}

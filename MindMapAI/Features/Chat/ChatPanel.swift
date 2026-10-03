import MindMapAICore
import SwiftUI

/// Ask About This Map: the questions, the answers with the topics they cite,
/// and the question field. It is content, so it has no Liquid Glass inside;
/// only its toolbar button does (docs/design-guidelines.md).
struct ChatPanel: View {
    @Bindable var chat: MapChat
    @Bindable var dictation: ChatDictation
    @FocusState private var isFieldFocused: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                    if chat.entries.isEmpty {
                        emptyState
                    }
                    if chat.showsLeftOutNotice {
                        Label("Earlier messages were left out to make room.", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(chat.entries) { entry in
                        ChatEntryView(chat: chat, entry: entry, onOpen: open)
                            .id(entry.id)
                    }
                }
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(.bottom)
            // Scrolling back through answers puts the keyboard away, as in Messages.
            .scrollDismissesKeyboard(.immediately)
            Divider()
            scopePicker
            dictationStatus
            composer
        }
        // `.contain` keeps the children's own identifiers, which UI tests use.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Chat.panel)
        .toolbar {
            ToolbarItem {
                Button("Clear Chat", systemImage: "trash", action: chat.requestClear)
                    .disabled(!chat.canClear)
                    .help(Text("Clear Chat"))
            }
        }
        .confirmationDialog("Clear the chat for this map?", isPresented: $chat.isConfirmingClear, titleVisibility: .visible) {
            Button("Clear Chat", role: .destructive, action: chat.clear)
        } message: {
            Text("Its questions and answers are deleted. This can’t be undone.")
        }
        .proChoicePaywall($dictation.paywall)
        // The microphone stays with the panel: closing it stops listening.
        .onDisappear(perform: dictation.end)
        .onChange(of: chat.selectableBranch) { chat.selectionChanged() }
        .onAppear { if chat.focusRequest { takeFocus() } }
        .onChange(of: chat.focusRequest) { _, requested in
            if requested { takeFocus() }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label {
                Text("Ask About This Map")
                    .font(.headline)
            } icon: {
                AISymbol()
            }
            Text("Ask a question about this map. Answers come from its topics and name the ones they use.")
                .foregroundStyle(.secondary)
            if let note = AIAvailabilityText.explanation(for: chat.modelAvailability) {
                // One line on why the chat cannot answer yet, in place of an alert.
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            suggestions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Questions to start with; tapping one asks it at once.
    private var suggestions: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(chat.suggestedQuestions, id: \.self) { question in
                Button {
                    chat.ask(suggestion: question)
                } label: {
                    Label(question, systemImage: "text.bubble")
                        .frame(maxWidth: .infinity, minHeight: Metrics.minimumHitTarget, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .disabled(!chat.canAskSuggestion)
                .accessibilityIdentifier(AccessibilityID.Chat.suggestion)
                .accessibilityHint(Text("Asks this question"))
            }
        }
        .padding(.top, Spacing.sm)
    }

    /// Whole map or the selected branch (FR-AI-11). The branch is offered
    /// only while one topic other than the central one is selected.
    private var scopePicker: some View {
        Picker(selection: $chat.asksAboutSelectedBranch) {
            Text("Whole Map").tag(false)
            if let branch = chat.selectableBranch {
                Text("Selected Branch: \(branch.title)").tag(true)
            }
        } label: {
            Text("Scope")
        }
        .pickerStyle(.menu)
        .fixedSize()
        .disabled(chat.selectableBranch == nil)
        .frame(maxWidth: .infinity, minHeight: Metrics.minimumHitTarget, alignment: .leading)
        .padding(.horizontal, Spacing.lg)
        .accessibilityIdentifier(AccessibilityID.Chat.scope)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: Spacing.sm) {
            TextField("Ask a Question", text: $chat.draft, prompt: Text("Ask about this map"), axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .focused($isFieldFocused)
                .accessibilityIdentifier(AccessibilityID.Chat.field)
                // Return asks; Shift-Return starts a new line.
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.shift) {
                        chat.draft += "\n"
                    } else {
                        ask()
                    }
                    return .handled
                }
                .onKeyPress(.escape) {
                    if dictation.isActive {
                        dictation.cancel()
                    } else {
                        // Back to the map, as Escape leaves other fields.
                        isFieldFocused = false
                    }
                    return .handled
                }
            microphone
            if chat.isAnswering {
                Button(action: chat.stop) {
                    composerIcon("Stop", systemImage: "stop.circle.fill")
                }
                .buttonStyle(.borderless)
                .help(Text("Stop"))
                .accessibilityIdentifier(AccessibilityID.Chat.stop)
            } else {
                Button(action: ask) {
                    composerIcon("Ask", systemImage: "arrow.up.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(!chat.canAsk)
                .help(Text("Ask"))
                .accessibilityIdentifier(AccessibilityID.Chat.send)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
    }

    /// Asking takes the draft as it is; listening stops so no late words
    /// start the next question.
    private func ask() {
        guard chat.canAsk else { return }
        dictation.end()
        chat.ask()
    }

    /// Ask by Voice (MM-80): the words heard go into the field, to be checked
    /// before Ask. Hidden where the chat cannot ask at all.
    @ViewBuilder
    private var microphone: some View {
        if dictation.isAvailable {
            switch dictation.phase {
            case .preparing, .downloading, .finishing:
                ProgressView()
                    .controlSize(.small)
                    .frame(minWidth: Metrics.minimumHitTarget, minHeight: Metrics.minimumHitTarget)
                    .accessibilityLabel(Text("Getting ready…"))
            case .listening:
                Button(action: dictation.stop) {
                    composerIcon("Stop Listening", systemImage: "mic.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tint)
                .help(Text("Stop Listening"))
                .accessibilityHint(Text("Listening. The words go into the question field."))
                .accessibilityIdentifier(AccessibilityID.Chat.microphone)
            case .idle, .needsDownload, .failed:
                Button(action: dictation.start) {
                    composerIcon("Ask by Voice", systemImage: "mic")
                }
                .buttonStyle(.borderless)
                .help(Text("Ask by Voice"))
                .accessibilityIdentifier(AccessibilityID.Chat.microphone)
            }
        }
    }

    /// One line on the dictation, above the field, while it needs one.
    @ViewBuilder
    private var dictationStatus: some View {
        let row = HStack(spacing: Spacing.sm) {
            switch dictation.phase {
            case .listening, .preparing, .finishing:
                Label(dictation.isListening ? LocalizedStringKey("Listening…") : LocalizedStringKey("Getting ready…"), systemImage: "waveform")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: dictation.cancel)
                    .accessibilityIdentifier(AccessibilityID.Chat.cancelVoice)
            case .needsDownload:
                Text("Voice input needs the \(Text(dictation.language.title)) speech model, which the system downloads once.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Download Speech Model", action: dictation.download)
            case .downloading(let fraction):
                ProgressView(value: fraction) {
                    Text("Downloading speech model…")
                }
                Button("Cancel", action: dictation.cancel)
            case .failed(let failure):
                Label(failure.message, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
            case .idle:
                EmptyView()
            }
        }
        if dictation.phase != .idle {
            row
                .font(.footnote)
                .frame(minHeight: Metrics.minimumHitTarget)
                .padding(.horizontal, Spacing.lg)
        }
    }

    /// The whole minimum hit target takes the tap, not just the symbol.
    private func composerIcon(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.iconOnly)
            .font(.title2)
            .frame(minWidth: Metrics.minimumHitTarget, minHeight: Metrics.minimumHitTarget)
            .contentShape(Rectangle())
    }

    private func takeFocus() {
        isFieldFocused = true
        chat.focusRequest = false
    }

    /// On iPhone the panel is a sheet over the map, so it steps aside to show the topic.
    private func open(_ citation: ChatCitation) {
        guard chat.open(citation) else { return }
        if sizeClass == .compact { chat.isPresented = false }
    }
}

/// One question and its answer.
private struct ChatEntryView: View {
    let chat: MapChat
    let entry: MapChat.Entry
    let onOpen: (ChatCitation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // No text selection here: on the Mac a selectable Text is an AppKit
            // text element, and with the label below SwiftUI and AppKit ask each
            // other for its label until the stack overflows (MM-82).
            Text(entry.question)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: Radius.lg))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel(Text("You asked: \(entry.question)"))
            if let branch = entry.branch {
                Label {
                    Text("Branch: \(branch.title)")
                } icon: {
                    Image(systemName: "arrow.triangle.branch")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(AccessibilityID.Chat.answerScope)
            }
            answer
        }
    }

    @ViewBuilder
    private var answer: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if !entry.displayAnswer.isEmpty {
                Text(entry.displayAnswer)
                    .textSelection(.enabled)
                    .accessibilityIdentifier(AccessibilityID.Chat.answer)
            }
            status
            if let suggestion = entry.suggestion {
                // Said by the app, not the model: the topics are only suggested.
                Label {
                    Text("Suggested \(suggestion.topics.count) topics under “\(suggestion.parentTitle)”. Review them on the map.")
                } icon: {
                    AISymbol()
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(AccessibilityID.Chat.suggestedTopics)
            }
            if !entry.citations.isEmpty {
                ChipFlowLayout(spacing: Spacing.xs) {
                    ForEach(entry.citations) { citation in
                        CitationChip(chat: chat, citation: citation, onOpen: onOpen)
                    }
                }
            }
            actions
            if entry.state == .complete {
                // HIG Generative AI: label what the model wrote and point to the sources.
                Label {
                    Text("Written by AI. Check the cited topics.")
                } icon: {
                    AISymbol()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Copy, Add to Note and Ask Again (MM-79). Copy and Add to Note need a
    /// finished answer; Ask Again is on the last question only, also after
    /// it stopped or failed.
    @ViewBuilder
    private var actions: some View {
        let isLast = entry.id == chat.entries.last?.id
        if entry.state == .complete || (isLast && !entry.isAnswering) {
            ChipFlowLayout(spacing: Spacing.xs) {
                if entry.state == .complete {
                    actionButton("Copy", systemImage: "doc.on.doc", id: AccessibilityID.Chat.copy) {
                        chat.copy(entry)
                    }
                    .disabled(!chat.canCopy(entry))
                    .help(Text("Copy the answer as plain text"))
                    actionButton("Add to Note", systemImage: "note.text.badge.plus", id: AccessibilityID.Chat.addToNote) {
                        chat.addToNote(entry)
                    }
                    .disabled(!chat.canAddToNote(entry))
                    .help(addToNoteHelp)
                    if chat.showsEntryPoints {
                        actionButton("Create Topics from Answer", systemImage: "plus.rectangle.on.rectangle", id: AccessibilityID.Chat.createTopics) {
                            chat.createTopics(from: entry)
                        }
                        .disabled(!chat.canCreateTopics(entry))
                        .help(createTopicsHelp)
                    }
                }
                if isLast {
                    actionButton("Ask Again", systemImage: "arrow.clockwise", id: AccessibilityID.Chat.askAgain) {
                        chat.askAgain(entry)
                    }
                    .disabled(!chat.canAskAgain(entry))
                    .help(Text("Ask this question again for a new answer"))
                }
            }
        }
    }

    /// Says where the answer would go, since the target is not on screen.
    private var addToNoteHelp: Text {
        guard let title = chat.noteTargetTitle(for: entry) else {
            return Text("Select one topic to add the answer to its note")
        }
        return Text("Add the answer to the note of “\(title)”")
    }

    private var createTopicsHelp: Text {
        guard let title = chat.topicsTargetTitle(for: entry) else {
            return Text("Select one topic to suggest the answer’s topics under it")
        }
        return Text("Suggest the answer’s points as topics under “\(title)”")
    }

    private func actionButton(_ title: LocalizedStringKey, systemImage: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.callout)
                .frame(minHeight: Metrics.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier(id)
    }

    @ViewBuilder
    private var status: some View {
        switch entry.state {
        case .answering(let isReadingMap):
            if entry.displayAnswer.isEmpty || isReadingMap {
                HStack(spacing: Spacing.sm) {
                    ProgressView()
                        .controlSize(.small)
                    Text(isReadingMap ? "Reading the map…" : "Thinking…")
                        .foregroundStyle(.secondary)
                }
            }
        case .stopped:
            Text("Stopped")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let failure):
            Label(failure.message, systemImage: "exclamationmark.circle")
                .foregroundStyle(.secondary)
        case .complete:
            EmptyView()
        }
    }
}

/// A topic an answer used. Clicking it shows the topic on the map; a topic
/// deleted since says so and does nothing.
private struct CitationChip: View {
    let chat: MapChat
    let citation: ChatCitation
    let onOpen: (ChatCitation) -> Void

    var body: some View {
        let exists = chat.exists(citation)
        Button {
            onOpen(citation)
        } label: {
            Label {
                Text(exists ? chat.title(of: citation) : citation.title)
                    .strikethrough(!exists)
                    .lineLimit(1)
            } icon: {
                Image(systemName: exists ? "smallcircle.filled.circle" : "circle.slash")
            }
            .font(.callout)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(minHeight: Metrics.minimumHitTarget)
        .disabled(!exists)
        .help(exists ? Text("Show Topic on Map") : Text("Topic no longer exists"))
        .accessibilityIdentifier(AccessibilityID.Chat.citation)
        .accessibilityValue(exists ? Text(verbatim: "") : Text("Topic no longer exists"))
    }
}

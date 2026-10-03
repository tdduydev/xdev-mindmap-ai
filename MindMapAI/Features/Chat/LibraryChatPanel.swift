import MindMapAICore
import SwiftUI

/// Ask About Library (MM-52): the panel beside the library list. Like Ask
/// About This Map's panel, it is content with no Liquid Glass inside, but it
/// has no scope picker, microphone or Add to Note: it reads every map and
/// writes to none.
struct LibraryChatPanel: View {
    @Bindable var chat: LibraryChat
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
                        LibraryChatEntryView(chat: chat, entry: entry, onOpen: open)
                            .id(entry.id)
                    }
                }
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.immediately)
            Divider()
            composer
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.LibraryChat.panel)
        .toolbar {
            ToolbarItem {
                Button("Clear Chat", systemImage: "trash", action: chat.clear)
                    .disabled(!chat.canClear)
                    .help(Text("Clear Chat"))
            }
        }
        .onAppear { if chat.focusRequest { takeFocus() } }
        .onChange(of: chat.focusRequest) { _, requested in
            if requested { takeFocus() }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label {
                Text("Ask About Library")
                    .font(.headline)
            } icon: {
                AISymbol()
            }
            Text("Ask a question about all your maps. Answers come from their topics and name the ones they use.")
                .foregroundStyle(.secondary)
            if let note = AIAvailabilityText.explanation(for: chat.modelAvailability) {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: Spacing.sm) {
            TextField("Ask a Question", text: $chat.draft, prompt: Text("Ask about your maps"), axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .focused($isFieldFocused)
                .accessibilityIdentifier(AccessibilityID.Chat.field)
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.shift) {
                        chat.draft += "\n"
                    } else {
                        chat.ask()
                    }
                    return .handled
                }
                .onKeyPress(.escape) {
                    isFieldFocused = false
                    return .handled
                }
            if chat.isAnswering {
                Button(action: chat.stop) {
                    composerIcon("Stop", systemImage: "stop.circle.fill")
                }
                .buttonStyle(.borderless)
                .help(Text("Stop"))
                .accessibilityIdentifier(AccessibilityID.Chat.stop)
            } else {
                Button(action: chat.ask) {
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

    /// On iPhone the panel is a sheet over the library, so it steps aside for the map.
    private func open(_ citation: ChatCitation) {
        chat.open(citation)
        if sizeClass == .compact { chat.isPresented = false }
    }
}

/// One question and its answer, with Copy and Ask Again.
private struct LibraryChatEntryView: View {
    let chat: LibraryChat
    let entry: LibraryChat.Entry
    let onOpen: (ChatCitation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // No text selection on the question: with its own label it loops
            // on the Mac (MM-82).
            Text(entry.question)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: Radius.lg))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel(Text("You asked: \(entry.question)"))
            if !entry.displayAnswer.isEmpty {
                Text(entry.displayAnswer)
                    .textSelection(.enabled)
                    .accessibilityIdentifier(AccessibilityID.Chat.answer)
            }
            status
            if !entry.citations.isEmpty {
                ChipFlowLayout(spacing: Spacing.xs) {
                    ForEach(entry.citations) { citation in
                        chip(for: citation)
                    }
                }
            }
            actions
            if entry.state == .complete {
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

    @ViewBuilder
    private var actions: some View {
        let isLast = entry.id == chat.entries.last?.id
        if entry.state == .complete || (isLast && !entry.isAnswering) {
            ChipFlowLayout(spacing: Spacing.xs) {
                if entry.state == .complete {
                    actionButton("Copy", systemImage: "doc.on.doc", id: AccessibilityID.Chat.copy) { chat.copy(entry) }
                        .disabled(!chat.canCopy(entry))
                        .help(Text("Copy the answer as plain text"))
                }
                if isLast {
                    actionButton("Ask Again", systemImage: "arrow.clockwise", id: AccessibilityID.Chat.askAgain) { chat.askAgain(entry) }
                        .disabled(!chat.canAskAgain(entry))
                        .help(Text("Ask this question again for a new answer"))
                }
            }
        }
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

    /// A cited topic; clicking it opens its map at the topic.
    private func chip(for citation: ChatCitation) -> some View {
        let exists = chat.exists(citation)
        return Button {
            onOpen(citation)
        } label: {
            Label {
                Text(citation.title)
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

    @ViewBuilder
    private var status: some View {
        switch entry.state {
        case .answering(let isReadingMap):
            if entry.displayAnswer.isEmpty || isReadingMap {
                HStack(spacing: Spacing.sm) {
                    ProgressView()
                        .controlSize(.small)
                    Text(isReadingMap ? "Reading your maps…" : "Thinking…")
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

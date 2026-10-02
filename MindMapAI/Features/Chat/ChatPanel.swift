import MindMapAICore
import SwiftUI

/// Ask About This Map: the questions, the answers with the topics they cite,
/// and the question field. It is content, so it has no Liquid Glass inside;
/// only its toolbar button does (docs/design-guidelines.md).
struct ChatPanel: View {
    @Bindable var chat: MapChat
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
            Divider()
            scopePicker
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
                        chat.ask()
                    }
                    return .handled
                }
                .onKeyPress(.escape) {
                    // Back to the map, as Escape leaves other fields.
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
            if !entry.citations.isEmpty {
                ChipFlowLayout(spacing: Spacing.xs) {
                    ForEach(entry.citations) { citation in
                        CitationChip(chat: chat, citation: citation, onOpen: onOpen)
                    }
                }
            }
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

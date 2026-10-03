import MindMapAICore
import SwiftUI

/// The sheet `AIAssistant` asks for: the first-use privacy notice, a request
/// to type, or a result to review before it touches the map.
struct AISheet: View {
    let assistant: AIAssistant
    let sheet: AIAssistant.Sheet

    var body: some View {
        Group {
            switch sheet {
            case .privacyNotice:
                AIPrivacyNotice(onContinue: assistant.acknowledgePrivacyNotice, onCancel: assistant.declinePrivacyNotice)
            case .generateMap(let draft):
                AIPromptForm(
                    title: "Generate Map",
                    message: "Describe the map you want, for example “Plan a product launch”. Suggestions appear on the canvas for you to review.",
                    placeholder: "Description",
                    actionTitle: "Generate",
                    allowsEmpty: false,
                    draft: draft,
                    onSubmit: assistant.generateMap(description:),
                    onCancel: { assistant.sheet = nil }
                )
            case .brainstorm(let nodeID, let draft):
                AIPromptForm(
                    title: "Brainstorm Ideas",
                    message: "Ask a question to focus the ideas, or leave it empty to brainstorm around the topic.",
                    placeholder: "Question (optional)",
                    actionTitle: "Brainstorm",
                    allowsEmpty: true,
                    draft: draft,
                    onSubmit: { assistant.brainstorm(nodeID, question: $0) },
                    onCancel: { assistant.sheet = nil }
                )
            case .rewrite(let rewrite):
                AIRewriteForm(
                    rewrite: rewrite,
                    onApply: { assistant.applyRewrite($0, from: rewrite) },
                    onCancel: { assistant.sheet = nil }
                )
            case .summary(let summary):
                AISummaryForm(
                    summary: summary,
                    onAddToNote: { assistant.addSummaryToNote(summary) },
                    onClose: { assistant.sheet = nil }
                )
            }
        }
        #if os(macOS)
        .frame(width: Metrics.aiSheetWidth)
        #endif
    }
}

/// FR-AI-19: shown before the first AI request, from a map or from the
/// library's chat (MM-52).
struct AIPrivacyNotice: View {
    let onContinue: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        Text("AI runs on this device")
                    } icon: {
                        AISymbol()
                    }
                    .font(.headline)
                    Text("MindMap AI uses Apple Intelligence on this device. Your maps and requests are processed here and are never sent to xDev.")
                    Text("AI can make mistakes. Suggestions change your map only when you accept them, and Undo takes them back.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text("Apple Intelligence"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue", action: onContinue)
                }
            }
        }
    }
}

/// A short request typed for Generate Map or Brainstorm Ideas.
private struct AIPromptForm: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let placeholder: LocalizedStringKey
    let actionTitle: LocalizedStringKey
    let allowsEmpty: Bool
    let onSubmit: (String) -> Void
    let onCancel: () -> Void
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        placeholder: LocalizedStringKey,
        actionTitle: LocalizedStringKey,
        allowsEmpty: Bool,
        draft: String,
        onSubmit: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.placeholder = placeholder
        self.actionTitle = actionTitle
        self.allowsEmpty = allowsEmpty
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        _text = State(initialValue: draft)
    }

    private var canSubmit: Bool {
        allowsEmpty || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(placeholder, text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($isFocused)
                        .accessibilityIdentifier(AccessibilityID.AISheet.promptField)
                } footer: {
                    Text(message)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text(title))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .accessibilityIdentifier(AccessibilityID.AISheet.cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(actionTitle) { onSubmit(text) }
                        .disabled(!canSubmit)
                        .accessibilityIdentifier(AccessibilityID.AISheet.submit)
                }
            }
            .onAppear { isFocused = true }
        }
    }
}

/// FR-AI-06: pick one of the rewritten titles, edit it if needed, then use it.
private struct AIRewriteForm: View {
    let rewrite: AIRewrite
    let onApply: (String) -> Void
    let onCancel: () -> Void
    @State private var choice: String
    @State private var title: String

    init(rewrite: AIRewrite, onApply: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.rewrite = rewrite
        self.onApply = onApply
        self.onCancel = onCancel
        let first = rewrite.suggestions.first ?? rewrite.originalTitle
        _choice = State(initialValue: first)
        _title = State(initialValue: first)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Current Title") {
                        Text(verbatim: rewrite.originalTitle)
                    }
                }
                Section {
                    Picker(selection: $choice) {
                        ForEach(rewrite.suggestions, id: \.self) { suggestion in
                            Text(verbatim: suggestion).tag(suggestion)
                        }
                    } label: {
                        Label {
                            Text("Suggested by AI")
                        } icon: {
                            AISymbol()
                        }
                    }
                    .pickerStyle(.inline)
                    TextField("New Title", text: $title, axis: .vertical)
                        .accessibilityIdentifier(AccessibilityID.AISheet.newTitle)
                } footer: {
                    Text("Edit the title before using it if you like.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text("Rewrite Topic"))
            .onChange(of: choice) { _, newChoice in title = newChoice }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .accessibilityIdentifier(AccessibilityID.AISheet.cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Title") { onApply(title) }
                        .accessibilityIdentifier(AccessibilityID.AISheet.useTitle)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

/// FR-AI-07: the summary is only read here; it goes into the note only with
/// Add to Note.
private struct AISummaryForm: View {
    let summary: AISummary
    let onAddToNote: () -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(verbatim: summary.text)
                        .textSelection(.enabled)
                        .accessibilityIdentifier(AccessibilityID.AISheet.summary)
                } header: {
                    Label {
                        Text("Suggested by AI")
                    } icon: {
                        AISymbol()
                    }
                } footer: {
                    if summary.isPartial {
                        Text("Written from part of the branch, which was too large to read in full.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text("Branch Summary"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                        .accessibilityIdentifier(AccessibilityID.AISheet.cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add to Note", action: onAddToNote)
                        .accessibilityIdentifier(AccessibilityID.AISheet.addToNote)
                }
            }
        }
    }
}

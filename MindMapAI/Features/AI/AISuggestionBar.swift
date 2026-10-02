import MindMapAICore
import MindMapDomain
import MindMapGraph
import SwiftUI

/// The glass bar over the editor while AI works or waits for a decision:
/// progress with Cancel, then the suggestions with Review, Discard and Accept
/// All, or a failure with a way forward. The map stays editable throughout
/// (FR-AI-15).
struct AISuggestionBar: View {
    @Bindable var assistant: AIAssistant
    @State private var isReviewing = false

    var body: some View {
        if assistant.isWorking || assistant.hasSuggestions || assistant.failure != nil {
            GlassEffectContainer {
                HStack(spacing: Spacing.md) {
                    leading
                    message
                    actions
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .glassEffect(in: Capsule())
            }
            .padding(Spacing.sm)
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder
    private var leading: some View {
        if assistant.isWorking {
            ProgressView()
                .controlSize(.small)
        } else if assistant.failure != nil {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        } else {
            AISymbol()
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var message: some View {
        if let failure = assistant.failure, !assistant.isWorking {
            Text(failure.message)
        } else if let activity = assistant.activity, !assistant.hasSuggestions {
            if activity.parts > 1 {
                Text("Summarizing part \(activity.part) of \(activity.parts)…")
            } else {
                Text(activity.feature.progressTitle)
            }
        } else if let feature = assistant.hasTagSuggestions ? AIFeature.suggestTags : assistant.suggestions?.feature {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(feature.suggestionsTitle)
                    .font(.headline)
                Text("\(assistant.suggestionCount) suggestions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if assistant.isWorking {
            Button("Cancel", action: assistant.cancel)
                .buttonStyle(.glass)
        } else if assistant.failure != nil {
            if assistant.canEditLastRequest {
                Button("Edit Request…", action: assistant.editLastRequest)
                    .buttonStyle(.glass)
            }
            Button("OK") { assistant.failure = nil }
                .buttonStyle(.glass)
        } else if assistant.hasSuggestions {
            Button("Review…") { isReviewing = true }
                .buttonStyle(.glass)
                .accessibilityIdentifier(AccessibilityID.Suggestions.review)
                .popover(isPresented: $isReviewing) {
                    if assistant.hasTagSuggestions {
                        AITagSuggestionList(assistant: assistant)
                    } else {
                        AISuggestionList(assistant: assistant)
                    }
                }
            Button("Discard", action: assistant.discardAll)
                .buttonStyle(.glass)
                .accessibilityIdentifier(AccessibilityID.Suggestions.discardAll)
            Button("Accept All", action: assistant.acceptAll)
                .buttonStyle(.glassProminent)
                .disabled(!assistant.canAcceptSuggestions)
                .accessibilityIdentifier(AccessibilityID.Suggestions.acceptAll)
        }
    }
}

/// Every suggestion with its own Accept and Discard and an editable title: the
/// way to review suggestions from the outline, the keyboard or VoiceOver.
struct AISuggestionList: View {
    @Bindable var assistant: AIAssistant

    var body: some View {
        if let suggestions = assistant.suggestions {
            List {
                Section {
                    ForEach(suggestions.topics) { topic in
                        AISuggestionRow(
                            topic: topic,
                            depth: depth(of: topic, in: suggestions),
                            canAccept: assistant.canAcceptSuggestions,
                            onRename: { assistant.renameSuggestion(topic.temporaryID, to: $0) },
                            onAccept: { assistant.accept(topic.temporaryID) },
                            onDiscard: { assistant.discard(topic.temporaryID) }
                        )
                    }
                } header: {
                    Label {
                        Text(suggestions.feature.suggestionsTitle)
                    } icon: {
                        AISymbol()
                    }
                } footer: {
                    Text("Suggested by AI on this device. Nothing changes until you accept.")
                }
            }
            .frame(minWidth: Metrics.suggestionListWidth, minHeight: Metrics.suggestionListHeight)
        }
    }

    private func depth(of topic: SuggestionState.Topic, in suggestions: SuggestionState) -> Int {
        var depth = 0
        var parent = topic.parentTemporaryID
        while let id = parent, let next = suggestions.topic(id) {
            depth += 1
            parent = next.parentTemporaryID
        }
        return depth
    }
}

private struct AISuggestionRow: View {
    let topic: SuggestionState.Topic
    let depth: Int
    let canAccept: Bool
    let onRename: (String) -> Void
    let onAccept: () -> Void
    let onDiscard: () -> Void
    @State private var draft: String

    init(
        topic: SuggestionState.Topic,
        depth: Int,
        canAccept: Bool,
        onRename: @escaping (String) -> Void,
        onAccept: @escaping () -> Void,
        onDiscard: @escaping () -> Void
    ) {
        self.topic = topic
        self.depth = depth
        self.canAccept = canAccept
        self.onRename = onRename
        self.onAccept = onAccept
        self.onDiscard = onDiscard
        _draft = State(initialValue: topic.title)
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            TextField("Topic", text: $draft)
                .onSubmit { onRename(draft) }
                .accessibilityLabel(Text("AI suggestion, \(topic.title)"))
            Button(action: onAccept) {
                Label("Accept Suggestion", systemImage: "checkmark.circle")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: Metrics.minimumHitTarget, minHeight: Metrics.minimumHitTarget)
            }
            .disabled(!canAccept)
            .help(Text("Accept Suggestion"))
            .accessibilityIdentifier(AccessibilityID.Suggestions.accept)
            Button(action: onDiscard) {
                Label("Discard Suggestion", systemImage: "xmark.circle")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: Metrics.minimumHitTarget, minHeight: Metrics.minimumHitTarget)
            }
            .help(Text("Discard Suggestion"))
            .accessibilityIdentifier(AccessibilityID.Suggestions.discard)
        }
        .buttonStyle(.borderless)
        .padding(.leading, CGFloat(depth) * Spacing.outlineIndent)
        .onChange(of: topic.title) { _, title in draft = title }
    }
}

/// Every suggested tag by topic, each with its own Accept and Discard and an
/// editable name: the review path for the outline, the keyboard and VoiceOver.
struct AITagSuggestionList: View {
    @Bindable var assistant: AIAssistant

    var body: some View {
        if let suggestions = assistant.tagSuggestions {
            List {
                ForEach(suggestions.nodeIDs, id: \.self) { nodeID in
                    Section {
                        ForEach(suggestions.suggestions(for: nodeID)) { suggestion in
                            AITagSuggestionRow(
                                suggestion: suggestion,
                                onRename: { assistant.renameTagSuggestion(suggestion.id, to: $0) },
                                onAccept: { assistant.acceptTag(suggestion.id) },
                                onDiscard: { assistant.discardTag(suggestion.id) }
                            )
                        }
                    } header: {
                        Text(verbatim: topicTitle(nodeID))
                    }
                }
                Section {
                } footer: {
                    Text("Suggested by AI on this device. Nothing changes until you accept.")
                }
            }
            .frame(minWidth: Metrics.suggestionListWidth, minHeight: Metrics.suggestionListHeight)
        }
    }

    private func topicTitle(_ nodeID: NodeID) -> String {
        let title = assistant.session.engine.state.node(nodeID)?.title ?? ""
        return title.isEmpty ? String(localized: "Untitled Topic") : title
    }
}

private struct AITagSuggestionRow: View {
    let suggestion: TagSuggestionState.Suggestion
    let onRename: (String) -> Void
    let onAccept: () -> Void
    let onDiscard: () -> Void
    @State private var draft: String

    init(
        suggestion: TagSuggestionState.Suggestion,
        onRename: @escaping (String) -> Void,
        onAccept: @escaping () -> Void,
        onDiscard: @escaping () -> Void
    ) {
        self.suggestion = suggestion
        self.onRename = onRename
        self.onAccept = onAccept
        self.onDiscard = onDiscard
        _draft = State(initialValue: suggestion.name)
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            TextField("Tag", text: $draft)
                .onSubmit { onRename(draft) }
                .accessibilityLabel(Text("AI suggested tag, \(suggestion.name)"))
            Button {
                // An edit not yet submitted is what the person means to accept.
                onRename(draft)
                onAccept()
            } label: {
                Label("Accept Tag", systemImage: "checkmark.circle")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: Metrics.minimumHitTarget, minHeight: Metrics.minimumHitTarget)
            }
            .help(Text("Accept Tag"))
            Button(action: onDiscard) {
                Label("Discard Tag", systemImage: "xmark.circle")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: Metrics.minimumHitTarget, minHeight: Metrics.minimumHitTarget)
            }
            .help(Text("Discard Tag"))
        }
        .buttonStyle(.borderless)
        .onChange(of: suggestion.name) { _, name in draft = name }
    }
}

import Foundation
import MindMapAICore
import MindMapDomain
import MindMapGraph
import Observation
import OSLog
import SwiftUI

/// Sizes of the requests the app sends, chosen in MM-8 within
/// `AIProposalLimits` [Đề xuất]: enough to be useful, few enough that the
/// first topics stream in quickly on the 4,096-token on-device model.
enum AIRequestDefaults {
    static let generatedMapTopics = 20
    static let expandedTopics = 6
    static let brainstormedTopics = 8
    static let missingTopics = 5
    /// A map description longer than this is a Pro request [Đề xuất].
    static let longDescriptionLength = 280
}

/// The AI side of one open map: runs requests in the background, holds the
/// suggestions apart from the graph, and turns what the person accepts into
/// commands through `EditorSession`, so AI never edits the map itself.
@Observable
final class AIAssistant {
    enum Sheet: Identifiable, Equatable {
        case privacyNotice
        case generateMap(draft: String)
        case brainstorm(NodeID, draft: String)
        case rewrite(AIRewrite)
        case summary(AISummary)

        var id: String {
            switch self {
            case .privacyNotice: "privacy"
            case .generateMap: "generate"
            case .brainstorm: "brainstorm"
            case .rewrite: "rewrite"
            case .summary: "summary"
            }
        }
    }

    /// The request in flight, for the progress line.
    struct Activity: Equatable {
        let feature: AIFeature
        /// Part n of m while a large branch is summarized in parts.
        var part = 0
        var parts = 0
    }

    let session: EditorSession
    let service: AIService
    private(set) var suggestions: SuggestionState?
    private(set) var activity: Activity?
    var failure: AIFailure?
    var sheet: Sheet?
    /// The suggestion selected on the canvas, by temporary ID.
    var selectedSuggestion: String?

    /// Called whenever the suggestions change, so the canvas lays them out.
    @ObservationIgnored var onSuggestionsChange: (() -> Void)?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var afterPrivacyNotice: (() -> Void)?
    /// What the person typed last, to offer it again after a refusal.
    @ObservationIgnored private var lastPrompt: Sheet?
    /// A generated map that lands in a map holding only its central topic
    /// also names the map when accepted.
    @ObservationIgnored private var namesMapOnAccept = false
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let locale: Locale

    static let privacyNoticeKey = "ai.privacyNoticeShown"

    init(session: EditorSession, service: AIService, defaults: UserDefaults = AppDefaults.store, locale: Locale = .current) {
        self.session = session
        self.service = service
        self.defaults = defaults
        self.locale = locale
    }

    // MARK: Reading

    var isWorking: Bool { activity != nil }
    var hasSuggestions: Bool { suggestions?.isEmpty == false }
    var canAcceptSuggestions: Bool { suggestions?.isComplete == true && hasSuggestions }
    /// Delete belongs to the selected suggestion, which the editor discards on
    /// Delete, or to the text field of a sheet; it is not Delete Topic's key then.
    var holdsDeleteKey: Bool { selectedSuggestion != nil || sheet != nil }

    /// Whether `feature` can run on `nodeID` (the selection when nil), and if
    /// not, why, for the one line the menus show.
    func availability(for feature: AIFeature, on nodeID: NodeID? = nil) -> AIAvailability {
        guard let capabilities = service.capabilities else { return .unknown }
        let language = feature == .generateMap ? AILanguage(preferredFor: locale) : language(for: target(nodeID))
        return capabilities.availability(for: feature, in: language)
    }

    /// The state behind every AI entry point at once, for the menu's one line.
    var modelAvailability: AIAvailability { service.modelState }

    func canRun(_ feature: AIFeature, on nodeID: NodeID? = nil) -> Bool {
        guard !isWorking, availability(for: feature, on: nodeID).isReady else { return false }
        if feature == .generateMap { return session.rootID != nil }
        guard let id = target(nodeID), let node = session.engine.state.node(id) else { return false }
        switch feature {
        case .rewrite:
            return !node.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .summarize:
            return !session.engine.state.childIDs(of: id).isEmpty
        case .generateMap, .expandTopic, .brainstorm, .findMissingTopics, .suggestTags:
            return true
        }
    }

    // MARK: Intents

    func requestGenerateMap() {
        guard canRun(.generateMap) else { return }
        afterNotice { [weak self] in
            self?.sheet = .generateMap(draft: "")
        }
    }

    /// FR-AI-03: a tree of topics under the central topic, from one description.
    func generateMap(description: String) {
        sheet = nil
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let rootID = session.rootID else { return }
        lastPrompt = .generateMap(draft: text)
        if text.count > AIRequestDefaults.longDescriptionLength, !isUnlocked(.generateMapFromDescription) { return }
        namesMapOnAccept = session.engine.state.childIDs(of: rootID).isEmpty
        let request = GenerateMapRequest(
            prompt: text,
            language: AILanguage.dominant(in: text, fallback: AILanguage(preferredFor: locale)),
            userLocaleIdentifier: locale.identifier,
            maximumTopics: AIRequestDefaults.generatedMapTopics
        )
        stream(.generateMap(request), anchor: rootID)
    }

    /// FR-AI-04.
    func expand(_ nodeID: NodeID? = nil) {
        guard canRun(.expandTopic, on: nodeID), let id = target(nodeID) else { return }
        afterNotice { [weak self] in
            guard let self, let context = self.context(for: id) else { return }
            self.stream(.expandTopic(ExpandTopicRequest(context: context, maximumTopics: AIRequestDefaults.expandedTopics)), anchor: id)
        }
    }

    func requestBrainstorm(_ nodeID: NodeID? = nil) {
        guard canRun(.brainstorm, on: nodeID), let id = target(nodeID) else { return }
        afterNotice { [weak self] in
            self?.sheet = .brainstorm(id, draft: "")
        }
    }

    /// FR-AI-05: ideas around the topic, or around a question the person typed.
    func brainstorm(_ nodeID: NodeID, question: String) {
        sheet = nil
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        lastPrompt = .brainstorm(nodeID, draft: text)
        guard let context = context(for: nodeID) else { return }
        let request = BrainstormRequest(
            context: context,
            question: text.isEmpty ? nil : text,
            maximumTopics: AIRequestDefaults.brainstormedTopics
        )
        stream(.brainstorm(request), anchor: nodeID)
    }

    /// FR-AI-08: offered as possibilities, not corrections.
    func findMissingTopics(_ nodeID: NodeID? = nil) {
        guard canRun(.findMissingTopics, on: nodeID), let id = target(nodeID) else { return }
        afterNotice { [weak self] in
            guard let self, self.isUnlocked(.findMissingIdeas), let context = self.context(for: id) else { return }
            self.stream(.findMissingTopics(MissingTopicsRequest(context: context, maximumTopics: AIRequestDefaults.missingTopics)), anchor: id)
        }
    }

    /// FR-AI-06.
    func rewrite(_ nodeID: NodeID? = nil, style: RewriteStyle) {
        guard canRun(.rewrite, on: nodeID), let id = target(nodeID) else { return }
        afterNotice { [weak self] in
            guard let self, let context = self.context(for: id) else { return }
            let provider = self.service.provider
            self.run(.rewrite) {
                try await provider.rewrite(RewriteRequest(context: context, style: style))
            } done: { [weak self] rewrite in
                self?.sheet = .rewrite(rewrite)
            }
        }
    }

    /// FR-AI-07: a summary of the branch, shown first; it goes into the note
    /// only if the person chooses Add to Note. A branch too large for one
    /// request is summarized in parts, then the parts are combined.
    func summarize(_ nodeID: NodeID? = nil) {
        guard canRun(.summarize, on: nodeID), let id = target(nodeID) else { return }
        afterNotice { [weak self] in
            guard let self else { return }
            if id == self.session.rootID, !self.isUnlocked(.summarizeWholeMap) { return }
            let state = self.session.engine.state
            let limits = AIContextLimits(contextSize: self.service.capabilities?.contextSize)
            let language = self.language(for: id)
            let localeIdentifier = self.locale.identifier
            let provider = self.service.provider
            self.run(.summarize) { [weak self] in
                let (whole, chunks) = try await Self.chunks(of: id, in: state, limits: limits, language: language, localeIdentifier: localeIdentifier)
                guard chunks.count > 1 else {
                    return try await provider.summarize(SummarizeRequest(context: chunks.first ?? whole))
                }
                var parts: [String] = []
                for (index, chunk) in chunks.enumerated() {
                    self?.activity?.part = index + 1
                    self?.activity?.parts = chunks.count
                    parts.append(try await provider.summarize(SummarizeRequest(context: chunk)).text)
                }
                return try await provider.summarize(SummarizeRequest(context: whole, partialSummaries: parts))
            } done: { [weak self] summary in
                self?.sheet = .summary(summary)
            }
        }
    }

    /// Stops the request in flight. Suggestions still streaming go too;
    /// complete ones stay for a decision.
    func cancel() {
        task?.cancel()
        task = nil
        activity = nil
        if suggestions?.isComplete == false { clearSuggestions() }
    }

    // MARK: Suggestions

    func acceptAll() {
        accept(nil)
    }

    func accept(_ temporaryID: String) {
        accept([temporaryID])
    }

    func discard(_ temporaryID: String) {
        suggestions?.remove(temporaryID)
        if selectedSuggestion == temporaryID { selectedSuggestion = nil }
        if suggestions?.isEmpty == true, !isWorking { clearSuggestions() } else { onSuggestionsChange?() }
    }

    func discardAll() {
        if suggestions?.isComplete == false { cancel() }
        clearSuggestions()
    }

    func renameSuggestion(_ temporaryID: String, to title: String) {
        suggestions?.rename(temporaryID, to: title)
        onSuggestionsChange?()
    }

    /// The suggestion drawn with `previewID` on the canvas, if any.
    func suggestionID(forPreview previewID: NodeID) -> String? {
        suggestions?.topic(previewID: previewID)?.temporaryID
    }

    // MARK: Results

    /// Sets one of the rewritten titles, possibly edited, as one undo step.
    func applyRewrite(_ title: String, from rewrite: AIRewrite) {
        sheet = nil
        do {
            let command = try ProposalTranslator.accept(title: title, from: rewrite, in: session.engine)
            session.perform(command, named: String(localized: "Rewrite Topic"))
        } catch {
            show(AIFailure(error))
        }
    }

    /// Adds the summary to the end of the topic's note, as one undo step.
    func addSummaryToNote(_ summary: AISummary) {
        sheet = nil
        do {
            let command = try ProposalTranslator.accept(summary, in: session.engine)
            session.perform(command, named: String(localized: "Add Summary to Note"))
        } catch {
            show(AIFailure(error))
        }
    }

    /// The request the person typed before a refusal, ready to reword.
    var canEditLastRequest: Bool { lastPrompt != nil && failure == .rephrase }

    func editLastRequest() {
        failure = nil
        sheet = lastPrompt
    }

    /// Waits for the request in flight, for tests.
    func requestSettled() async {
        await task?.value
    }

    // MARK: Privacy notice (FR-AI-19)

    func acknowledgePrivacyNotice() {
        defaults.set(true, forKey: Self.privacyNoticeKey)
        sheet = nil
        let action = afterPrivacyNotice
        afterPrivacyNotice = nil
        action?()
    }

    func declinePrivacyNotice() {
        afterPrivacyNotice = nil
        sheet = nil
    }

    /// A sheet closed without its buttons (swipe down, Esc): nothing runs.
    func sheetDismissed() {
        if sheet == nil { afterPrivacyNotice = nil }
    }

    // MARK: Running

    private func afterNotice(_ action: @escaping () -> Void) {
        if defaults.bool(forKey: Self.privacyNoticeKey) {
            action()
        } else {
            afterPrivacyNotice = action
            sheet = .privacyNotice
        }
    }

    private func stream(_ request: SuggestionRequest, anchor: NodeID) {
        cancel()
        failure = nil
        selectedSuggestion = nil
        suggestions = SuggestionState(feature: request.feature, anchorID: anchor)
        activity = Activity(feature: request.feature)
        onSuggestionsChange?()
        let feature = request.feature
        let provider = service.provider
        let started = ContinuousClock.now
        task = Task { [weak self] in
            var reportedFirst = false
            do {
                for try await snapshot in provider.streamSuggestions(request) {
                    guard let self, !Task.isCancelled else { return }
                    self.suggestions?.update(with: snapshot)
                    if !reportedFirst, self.hasSuggestions {
                        reportedFirst = true
                        // NFR-PERF-07 is measured from this line; it carries no map content.
                        let milliseconds = Int((ContinuousClock.now - started) / .milliseconds(1))
                        Log.ai.info("AI \(feature.rawValue, privacy: .public) first suggestion after \(milliseconds, privacy: .public) ms")
                    }
                    self.onSuggestionsChange?()
                }
                guard let self, !Task.isCancelled else { return }
                self.finishSuggestions()
            } catch is CancellationError {
            } catch {
                self?.fail(error, feature: feature)
            }
        }
    }

    private func finishSuggestions() {
        activity = nil
        task = nil
        guard canAcceptSuggestions, let suggestions else {
            clearSuggestions()
            show(.nothingSuggested)
            return
        }
        AccessibilityNotification.Announcement(String(localized: "\(suggestions.topics.count) AI suggestions")).post()
    }

    private func run<Result: Sendable>(
        _ feature: AIFeature,
        work: @escaping () async throws -> Result,
        done: @escaping (Result) -> Void
    ) {
        cancel()
        failure = nil
        activity = Activity(feature: feature)
        task = Task { [weak self] in
            do {
                let result = try await work()
                guard let self, !Task.isCancelled else { return }
                self.activity = nil
                self.task = nil
                done(result)
            } catch is CancellationError {
            } catch {
                self?.fail(error, feature: feature)
            }
        }
    }

    private func accept(_ temporaryIDs: Set<String>?) {
        guard let suggestions, suggestions.isComplete else { return }
        do {
            let accepted = try suggestions.accept(temporaryIDs, in: session.engine)
            var commands = accepted.command.commands
            if suggestions.feature == .generateMap, namesMapOnAccept,
               let title = suggestions.suggestedMapTitle, !title.isEmpty, let rootID = session.rootID {
                // The new map takes the generated title, in the same undo step.
                commands.append(RenameMapCommand(title: title))
                commands.append(UpdateNodeCommand(nodeID: rootID, .title(title)))
            }
            guard session.perform(BatchCommand(commands), named: String(localized: "Add AI Topics")) else {
                show(.unusable)
                return
            }
            namesMapOnAccept = false
            self.suggestions?.didAccept(accepted.nodeIDs)
            if let selectedSuggestion, accepted.nodeIDs[selectedSuggestion] != nil { self.selectedSuggestion = nil }
            if self.suggestions?.isEmpty == true { clearSuggestions() } else { onSuggestionsChange?() }
        } catch {
            show(AIFailure(error))
            if case .topicGone = AIFailure(error) { clearSuggestions() }
        }
    }

    private func clearSuggestions() {
        guard suggestions != nil else { return }
        suggestions = nil
        selectedSuggestion = nil
        onSuggestionsChange?()
    }

    private func fail(_ error: any Error, feature: AIFeature) {
        activity = nil
        task = nil
        if suggestions?.isComplete == false { clearSuggestions() }
        show(AIFailure(error))
    }

    private func show(_ failure: AIFailure) {
        self.failure = failure
        AccessibilityNotification.Announcement(failure.message).post()
    }

    private func isUnlocked(_ feature: ProFeature) -> Bool {
        guard service.entitlements.allows(feature) else {
            show(.requiresPro)
            return false
        }
        return true
    }

    // MARK: Context

    private func target(_ nodeID: NodeID?) -> NodeID? {
        nodeID ?? session.selection
    }

    /// The language of the topic: Vietnamese text gets a Vietnamese answer even
    /// on an English system, and the other way round (FR-AI-13).
    private func language(for nodeID: NodeID?) -> AILanguage {
        let fallback = AILanguage(preferredFor: locale)
        guard let nodeID, let node = session.engine.state.node(nodeID) else { return fallback }
        return AILanguage.dominant(in: [session.map.title, node.title].joined(separator: ". "), fallback: fallback)
    }

    private func context(for nodeID: NodeID) -> AIContext? {
        let builder = AIContextBuilder(limits: AIContextLimits(contextSize: service.capabilities?.contextSize))
        do {
            return try builder.context(
                for: nodeID,
                in: session.engine.state,
                language: language(for: nodeID),
                userLocaleIdentifier: locale.identifier
            )
        } catch {
            show(.topicGone)
            return nil
        }
    }

    /// The bounded context of the branch, which also frames the combining
    /// request, and the branch in parts that each fit. Splitting a whole map
    /// walks every topic, so it runs off the main actor.
    @concurrent
    private nonisolated static func chunks(
        of nodeID: NodeID,
        in state: GraphState,
        limits: AIContextLimits,
        language: AILanguage,
        localeIdentifier: String
    ) async throws -> (whole: AIContext, chunks: [AIContext]) {
        let builder = AIContextBuilder(limits: limits)
        let whole = try builder.context(for: nodeID, in: state, language: language, userLocaleIdentifier: localeIdentifier)
        guard whole.isTruncated else { return (whole, [whole]) }
        return (whole, try builder.chunkContexts(for: nodeID, in: state, language: language, userLocaleIdentifier: localeIdentifier))
    }
}

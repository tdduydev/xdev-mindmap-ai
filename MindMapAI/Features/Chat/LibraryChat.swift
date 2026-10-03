import Foundation
import MindMapAICore
import MindMapDomain
import MindMapQuery
import Observation
import SwiftUI

/// Ask across the library (docs/chat.md, C3): one conversation per library
/// window about every live map, never Recently Deleted.
///
/// Pro (decided 2026-10-02): it asks `ProEntitlement.allows(.askLibrary)`
/// before it opens and before each question, and opens the paywall instead.
/// It only reads, so it has no suggestions and no Add to Note: no map is the
/// obvious target. It belongs to no map, so it is not saved (MM-55 saves per
/// map); closing the window ends it. It is map content: never logged.
@Observable
final class LibraryChat {
    typealias Entry = MapChat.Entry

    let service: AIService
    private(set) var entries: [Entry] = []
    var draft = ""
    var isPresented = false {
        didSet { if isPresented, !oldValue { focusRequest = true } }
    }
    var focusRequest = false
    private(set) var showsLeftOutNotice = false
    /// Set when the person needs Pro first; the sheet's choice runs once Pro is unlocked.
    var paywall: PendingProChoice?
    /// The on-device notice before the first AI request (FR-AI-19), as in a map.
    var isShowingPrivacyNotice = false
    /// Cited topics found gone when opened: their chips say so.
    private(set) var missingCitations: Set<TopicRef> = []

    @ObservationIgnored private var conversation: (any ChatConversation)?
    /// Observed: the composer swaps Stop back to Ask when it ends.
    private var task: Task<Void, Never>?
    @ObservationIgnored private var hasNoticedLeftOut = false
    @ObservationIgnored private var afterPrivacyNotice: (() -> Void)?
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let copyText: @MainActor (String) -> Void
    /// Opens the cited topic's map and shows the topic; false when it is gone.
    @ObservationIgnored private let openTopic: @MainActor (ChatCitation) async -> Bool
    @ObservationIgnored private var opening: Task<Void, Never>?

    init(
        service: AIService,
        defaults: UserDefaults = AppDefaults.store,
        locale: Locale = .current,
        copyText: @escaping @MainActor (String) -> Void = Clipboard.copy,
        openTopic: @escaping @MainActor (ChatCitation) async -> Bool
    ) {
        self.service = service
        self.defaults = defaults
        self.locale = locale
        self.copyText = copyText
        self.openTopic = openTopic
    }

    // MARK: Reading

    /// Hidden where AI is hidden, as Ask in a map is.
    var showsEntryPoints: Bool { service.showsControls && service.chatProvider != nil }

    var isUnlocked: Bool { service.entitlements.allows(.askLibrary) }

    var modelAvailability: AIAvailability { service.modelState }

    var isAnswering: Bool { task != nil }

    var canAsk: Bool {
        canAskSuggestion && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canAskSuggestion: Bool {
        showsEntryPoints && !isAnswering && modelAvailability.isReady
    }

    var canClear: Bool { !entries.isEmpty }

    /// Questions to start with, in the app's language like Ask in a map's.
    var suggestedQuestions: [String] {
        [
            String(localized: "What are my maps about?"),
            String(localized: "Which maps have topics in common?"),
            String(localized: "What should I work on next?"),
        ]
    }

    /// The finished turns, as a provider takes them back.
    var turns: [ChatTurn] {
        entries.compactMap { entry in
            guard entry.state == .complete else { return nil }
            return ChatTurn(id: entry.id, question: entry.question, answer: entry.answer, citations: entry.citations)
        }
    }

    func exists(_ citation: ChatCitation) -> Bool {
        !missingCitations.contains(TopicRef(mapID: citation.mapID, nodeID: citation.nodeID))
    }

    var lastAnswer: Entry? {
        entries.last.flatMap { $0.state == .complete ? $0 : nil }
    }

    func canCopy(_ entry: Entry) -> Bool {
        entry.state == .complete && !entry.displayAnswer.isEmpty
    }

    func canAskAgain(_ entry: Entry) -> Bool {
        entry.id == entries.last?.id && !entry.isAnswering && canAskSuggestion
    }

    var canCopyLastAnswer: Bool { lastAnswer.map(canCopy) ?? false }
    var canAskLastQuestionAgain: Bool { entries.last.map(canAskAgain) ?? false }

    // MARK: Intents

    /// AI ▸ Ask About Library…: the panel with the field focused, or the
    /// paywall without Pro, which opens the panel if Pro is unlocked there.
    func present() {
        guard showsEntryPoints else { return }
        guard isUnlocked else {
            paywall = PendingProChoice(feature: .askLibrary) { [weak self] in self?.present() }
            return
        }
        if isPresented { focusRequest = true } else { isPresented = true }
    }

    /// The toolbar button: shows or hides the panel.
    func toggle() {
        if isPresented { isPresented = false } else { present() }
    }

    func ask() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canAsk else { return }
        ask(question, clearsDraft: true)
    }

    func ask(suggestion: String) {
        guard canAskSuggestion else { return }
        ask(suggestion, clearsDraft: false)
    }

    /// Pro is checked at each question too: it can lapse while the panel is open.
    private func ask(_ question: String, clearsDraft: Bool) {
        guard let provider = service.chatProvider else { return }
        guard isUnlocked else {
            paywall = PendingProChoice(feature: .askLibrary) { [weak self] in self?.ask(question, clearsDraft: clearsDraft) }
            return
        }
        afterPrivacyNoticeShown { [weak self] in
            self?.send(question, clearsDraft: clearsDraft, with: provider)
        }
    }

    func stop() {
        guard let task else { return }
        task.cancel()
        self.task = nil
        if let index = entries.indices.last, entries[index].isAnswering {
            entries[index].state = .stopped
        }
    }

    /// Nothing is saved, so clearing needs no question first.
    func clear() {
        stop()
        entries = []
        conversation = nil
        showsLeftOutNotice = false
        hasNoticedLeftOut = false
        missingCitations = []
    }

    func copy(_ entry: Entry) {
        guard canCopy(entry) else { return }
        copyText(entry.displayAnswer)
        AccessibilityNotification.Announcement(String(localized: "Answer copied")).post()
    }

    /// Asks the last question again in place of its answer; the model starts
    /// from the turns before it.
    func askAgain(_ entry: Entry) {
        guard canAskAgain(entry), isUnlocked, let provider = service.chatProvider else { return }
        afterPrivacyNoticeShown { [weak self] in
            guard let self, self.canAskAgain(entry) else { return }
            self.entries.removeLast()
            self.conversation = nil
            self.send(entry.question, clearsDraft: false, with: provider)
        }
    }

    func copyLastAnswer() { lastAnswer.map(copy) }
    func askLastQuestionAgain() { entries.last.map(askAgain) }

    /// Opens the cited topic's map and shows the topic. A topic or map gone
    /// since keeps its chip, struck through, and VoiceOver says why.
    func open(_ citation: ChatCitation) {
        opening = Task { [weak self] in
            guard let self else { return }
            guard await self.openTopic(citation) else {
                self.missingCitations.insert(TopicRef(mapID: citation.mapID, nodeID: citation.nodeID))
                AccessibilityNotification.Announcement(String(localized: "Topic no longer exists")).post()
                return
            }
        }
    }

    /// Waits for the answer in flight and a citation being opened, for tests.
    func answerSettled() async {
        await task?.value
        await opening?.value
    }

    // MARK: Privacy notice

    func acknowledgePrivacyNotice() {
        defaults.set(true, forKey: AIAssistant.privacyNoticeKey)
        isShowingPrivacyNotice = false
        let action = afterPrivacyNotice
        afterPrivacyNotice = nil
        action?()
    }

    func declinePrivacyNotice() {
        afterPrivacyNotice = nil
        isShowingPrivacyNotice = false
    }

    private func afterPrivacyNoticeShown(_ action: @escaping () -> Void) {
        if defaults.bool(forKey: AIAssistant.privacyNoticeKey) {
            action()
        } else {
            afterPrivacyNotice = action
            isShowingPrivacyNotice = true
        }
    }

    // MARK: Sending

    private func send(_ question: String, clearsDraft: Bool, with provider: any ChatProvider) {
        guard !isAnswering else { return }
        if clearsDraft { draft = "" }
        let conversation = self.conversation ?? provider.conversation(in: .library, history: turns)
        self.conversation = conversation
        let entry = Entry(id: UUID(), question: question, answer: "", citations: [], state: .answering(isReadingMap: false))
        entries.append(entry)
        let message = ChatMessage(
            text: question,
            language: AILanguage.dominant(in: question, fallback: AILanguage(preferredFor: locale)),
            userLocaleIdentifier: locale.identifier
        )
        task = Task { [weak self] in
            do {
                for try await update in conversation.send(message) {
                    guard let self, !Task.isCancelled else { return }
                    self.apply(update, to: entry.id)
                }
                guard let self, !Task.isCancelled else { return }
                self.finish(entry.id)
            } catch is CancellationError {
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.fail(entry.id, error)
            }
        }
    }

    private func apply(_ update: ChatUpdate, to id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].answer = update.text
        entries[index].citations = update.citations
        entries[index].state = update.isComplete ? .complete : .answering(isReadingMap: update.isReadingMap)
        if update.leftOutEarlierTurns, !hasNoticedLeftOut {
            hasNoticedLeftOut = true
            showsLeftOutNotice = true
        }
    }

    private func finish(_ id: UUID) {
        task = nil
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        if entries[index].isAnswering { entries[index].state = .complete }
        AccessibilityNotification.Announcement(entries[index].displayAnswer).post()
    }

    private func fail(_ id: UUID, _ error: any Error) {
        task = nil
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let failure = ChatFailure(error)
        entries[index].state = .failed(failure)
        AccessibilityNotification.Announcement(failure.message).post()
    }
}

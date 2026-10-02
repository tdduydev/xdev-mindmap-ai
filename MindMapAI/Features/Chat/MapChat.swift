import Foundation
import MindMapAICore
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import Observation
import OSLog
import SwiftUI

/// Ask in a map (docs/chat.md, C1): one conversation about one open map.
///
/// It sends questions to the chat provider, which reads the map through
/// tools, and shows the answers with their citations. It never edits the map:
/// opening a citation selects the topic, and only revealing a collapsed one is
/// an undo step, as in Find. Each finished turn is saved with the map (MM-55),
/// so opening the map again shows the conversation and the model sees as much
/// of it as fits. The chat is map content: it is never logged.
@Observable
final class MapChat {
    /// One question and its answer, as the panel shows them.
    struct Entry: Identifiable, Equatable {
        enum State: Equatable {
            case answering(isReadingMap: Bool)
            case complete
            /// Stopped by the person; what arrived stays.
            case stopped
            case failed(ChatFailure)
        }

        let id: UUID
        let question: String
        /// The answer as written, handles included.
        var answer: String
        var citations: [ChatCitation]
        /// The branch the question was limited to; nil for the whole map.
        var branch: ChatBranch? = nil
        var state: State

        var displayAnswer: String { CitationTable.displayText(answer) }
        var isAnswering: Bool {
            if case .answering = state { return true }
            return false
        }
    }

    let session: EditorSession
    let assistant: AIAssistant
    private(set) var entries: [Entry] = []
    /// What the person is typing.
    var draft = ""
    /// Whether the panel shows: beside the map on the Mac and iPad, a sheet on iPhone.
    var isPresented = false {
        didSet { if isPresented, !oldValue { focusRequest = true } }
    }
    /// Asks the question field to take focus, as Ask About This Map does.
    var focusRequest = false
    /// "Earlier messages were left out", said once per conversation.
    private(set) var showsLeftOutNotice = false
    /// Clear Chat asks first: the saved conversation cannot be undone.
    var isConfirmingClear = false
    /// The topic the person limited the questions to (MM-78). It holds only
    /// while that topic stays selected: selecting nothing or another topic
    /// goes back to the whole map, so a question never reads a branch the
    /// person no longer sees as chosen.
    private(set) var branchChoice: NodeID?

    @ObservationIgnored private var conversation: (any ChatConversation)?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var hasNoticedLeftOut = false
    @ObservationIgnored private let locale: Locale
    /// Saves and clears in order, so a clear cannot overtake the save before it.
    @ObservationIgnored private var lastWrite: Task<Void, Never>?

    /// `history` is the map's saved chat, oldest first.
    init(session: EditorSession, assistant: AIAssistant, history: [ChatTurn] = [], locale: Locale = .current) {
        self.session = session
        self.assistant = assistant
        self.locale = locale
        entries = history.map { turn in
            Entry(id: turn.id, question: turn.question, answer: turn.answer, citations: turn.citations, branch: turn.branch, state: .complete)
        }
    }

    var service: AIService { assistant.service }

    // MARK: Reading

    /// Hidden where AI is hidden: an Intel Mac, an ineligible device (MM-21),
    /// or Use AI Features turned off in Settings (MM-44). An open panel keeps
    /// its answers but cannot ask again.
    var showsEntryPoints: Bool { service.showsControls && service.chatProvider != nil }

    /// The model's state, for the one line the panel shows when it is not ready.
    var modelAvailability: AIAvailability { service.modelState }

    var isAnswering: Bool { task != nil }

    var canAsk: Bool {
        canAskSuggestion && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A suggested question needs no draft.
    var canAskSuggestion: Bool {
        showsEntryPoints && !isAnswering && modelAvailability.isReady
    }

    // MARK: Scope

    /// The branch the scope picker offers: the one selected topic, unless it
    /// is the central topic, whose branch is the whole map anyway.
    var selectableBranch: ChatBranch? {
        guard session.selectedIDs.count == 1, let id = session.selection, id != session.rootID,
              let node = session.engine.state.node(id) else { return nil }
        let title = node.title.split(whereSeparator: \.isNewline).joined(separator: " ")
        return ChatBranch(nodeID: id, title: title.isEmpty ? String(localized: "Untitled Topic") : title)
    }

    /// What the next question reads: the chosen branch while it is still the
    /// selection, else the whole map (nil).
    var branch: ChatBranch? {
        guard let branchChoice, let selectable = selectableBranch, selectable.nodeID == branchChoice else { return nil }
        return selectable
    }

    /// The scope picker: true limits the questions to the selected branch.
    var asksAboutSelectedBranch: Bool {
        get { branch != nil }
        set { branchChoice = newValue ? selectableBranch?.nodeID : nil }
    }

    /// Drops a branch choice the selection has left, so selecting the topic
    /// again later does not quietly bring it back.
    func selectionChanged() {
        if branch == nil { branchChoice = nil }
    }

    /// Questions to start with, as buttons in an empty chat (FR-AI-09): about
    /// the branch when the scope is one, else about the map. Asked as written,
    /// so the answer is in the app's language.
    var suggestedQuestions: [String] {
        if branch != nil {
            [
                String(localized: "Summarize this branch"),
                String(localized: "What is missing in this branch?"),
                String(localized: "What are the next steps for this branch?"),
            ]
        } else {
            [
                String(localized: "Summarize this map"),
                String(localized: "What is missing?"),
                String(localized: "What are the next steps?"),
            ]
        }
    }


    var canClear: Bool { !entries.isEmpty }

    /// The finished turns, as a provider takes them back.
    var turns: [ChatTurn] {
        entries.compactMap { entry in
            guard entry.state == .complete else { return nil }
            return ChatTurn(id: entry.id, question: entry.question, answer: entry.answer, citations: entry.citations, branch: entry.branch)
        }
    }

    /// Whether a cited topic is still in the map.
    func exists(_ citation: ChatCitation) -> Bool {
        citation.mapID == session.map.id && session.engine.state.node(citation.nodeID) != nil
    }

    /// The topic's current title: it may have been renamed since the answer.
    func title(of citation: ChatCitation) -> String {
        session.engine.state.node(citation.nodeID)?.title ?? citation.title
    }

    // MARK: Intents

    /// AI ▸ Ask About This Map… (⌃⌘A): shows the panel with the field focused.
    func present() {
        guard showsEntryPoints else { return }
        if isPresented { focusRequest = true } else { isPresented = true }
    }

    func ask() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canAsk else { return }
        ask(question, clearsDraft: true)
    }

    /// A suggested question: asked at once, the draft left as it is.
    func ask(suggestion: String) {
        guard canAskSuggestion else { return }
        ask(suggestion, clearsDraft: false)
    }

    private func ask(_ question: String, clearsDraft: Bool) {
        guard let provider = service.chatProvider else { return }
        // The scope is taken now: the person may select something else
        // while the privacy notice is up.
        let branch = branch
        assistant.afterPrivacyNoticeShown { [weak self] in
            self?.send(question, about: branch, clearsDraft: clearsDraft, with: provider)
        }
    }

    /// Stops the answer; what arrived so far stays, marked as stopped.
    func stop() {
        guard let task else { return }
        task.cancel()
        self.task = nil
        if let index = entries.indices.last, entries[index].isAnswering {
            entries[index].state = .stopped
        }
    }

    /// AI ▸ Clear Chat: shows the panel and asks before clearing.
    func requestClear() {
        guard canClear else { return }
        isPresented = true
        isConfirmingClear = true
    }

    /// Empties the panel, deletes the saved chat and starts a new conversation.
    func clear() {
        stop()
        entries = []
        conversation = nil
        showsLeftOutNotice = false
        hasNoticedLeftOut = false
        let mapID = session.map.id
        write { repository in try await repository.clearChat(for: mapID) }
    }

    /// Opens a cited topic: selects it, reveals it if collapsed, and scrolls
    /// to it. False when the topic no longer exists.
    @discardableResult
    func open(_ citation: ChatCitation) -> Bool {
        guard citation.mapID == session.map.id else { return false }
        return session.showTopic(citation.nodeID)
    }

    /// Waits for the answer in flight and the writes it queued, for tests.
    func answerSettled() async {
        await task?.value
        await lastWrite?.value
    }

    // MARK: Sending

    private func send(_ question: String, about branch: ChatBranch?, clearsDraft: Bool, with provider: any ChatProvider) {
        guard !isAnswering else { return }
        if clearsDraft { draft = "" }
        let conversation = self.conversation ?? provider.conversation(in: .map(session.map.id), history: turns)
        self.conversation = conversation
        let entry = Entry(id: UUID(), question: question, answer: "", citations: [], branch: branch, state: .answering(isReadingMap: false))
        entries.append(entry)
        let message = ChatMessage(
            text: question,
            language: AILanguage.dominant(in: question, fallback: AILanguage(preferredFor: locale)),
            userLocaleIdentifier: locale.identifier,
            branch: branch
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
        let entry = entries[index]
        let turn = ChatTurn(id: entry.id, question: entry.question, answer: entry.answer, citations: entry.citations, branch: entry.branch)
        let mapID = session.map.id
        write { repository in try await repository.appendChatTurn(turn, to: mapID, at: .now) }
        // VoiceOver hears the whole answer once, not each streamed word.
        AccessibilityNotification.Announcement(entries[index].displayAnswer).post()
    }

    /// A failed write leaves the panel as it is; the turn is only missing
    /// next time the map opens. The error, never the chat, is logged.
    private func write(_ body: @escaping @Sendable (any MapRepository) async throws -> Void) {
        let previous = lastWrite
        let repository = session.repository
        lastWrite = Task {
            await previous?.value
            do {
                try await body(repository)
            } catch {
                Log.persistence.error("Saving the chat failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func fail(_ id: UUID, _ error: any Error) {
        task = nil
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let failure = ChatFailure(error)
        entries[index].state = .failed(failure)
        AccessibilityNotification.Announcement(failure.message).post()
    }
}

/// Why a question got no answer, as the person needs to hear it (FR-AI-14).
enum ChatFailure: Hashable {
    /// Guardrails or a refusal. The app never rewords the question itself.
    case rephrase
    case tooLong
    case busy
    case unavailable(AIAvailability)
    case unsupportedLanguage
    case noAnswer

    init(_ error: any Error) {
        guard let error = error as? AIError else {
            self = .noAnswer
            return
        }
        switch error {
        case .guardrailViolation, .refusal: self = .rephrase
        case .contextSizeExceeded: self = .tooLong
        case .rateLimited: self = .busy
        case .unavailable(.languageUnsupported), .unsupportedLanguage: self = .unsupportedLanguage
        case .unavailable(let availability): self = .unavailable(availability)
        case .invalidResponse, .generationFailed: self = .noAnswer
        }
    }

    var message: String {
        switch self {
        case .rephrase:
            String(localized: "This request couldn’t be completed. Try wording it differently.")
        case .tooLong:
            String(localized: "This question needs more room than the chat has. Clear the chat or ask about a smaller part of the map.")
        case .busy:
            String(localized: "Apple Intelligence is busy. Try again in a moment.")
        case .unavailable(let availability):
            AIAvailabilityText.explanation(for: availability) ?? String(localized: "Apple Intelligence isn’t available right now.")
        case .unsupportedLanguage:
            String(localized: "Apple Intelligence doesn’t support the language of this question yet.")
        case .noAnswer:
            String(localized: "No answer this time. Try again or ask another way.")
        }
    }
}

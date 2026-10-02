import Foundation
@testable import MindMapAI
import MindMapAICore
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import MindMapTestSupport
import Testing

/// Ask in a map end to end without a model: `MockChatProvider` answers, a real
/// session on an in-memory store shows what the answers cite.
@Suite("Map chat")
struct MapChatTests {
    let repository: SwiftDataMapRepository
    let chatProvider = MockChatProvider()
    let defaults: UserDefaults

    init() throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
        defaults = try #require(UserDefaults(suiteName: "MapChatTests.\(UUID().uuidString)"))
        defaults.set(true, forKey: AIAssistant.privacyNoticeKey)
    }

    /// A map "Launch" with Plan > Beta and Budget.
    private func open(capabilities: AICapabilities = .readyForTesting, hasChat: Bool = true) async throws -> MapChat {
        var engine = try GraphEngine(state: GraphState.newMap(title: "Launch"))
        let rootID = try #require(engine.state.map.rootNodeID)
        let planID = NodeID()
        try engine.execute(AddNodeCommand(nodeID: planID, .child(of: rootID), title: "Plan"))
        try engine.execute(AddNodeCommand(.child(of: planID), title: "Beta"))
        try engine.execute(AddNodeCommand(.child(of: rootID), title: "Budget"))
        try await repository.create(engine.state)
        guard case .ready(let session) = await EditorSession.open(mapID: engine.state.map.id, repository: repository, onMapChange: { _ in }) else {
            throw OpenFailed()
        }
        let aiProvider = MockAIProvider(capabilities: capabilities)
        chatProvider.setCapabilities(capabilities)
        let service = AIService(
            provider: { aiProvider },
            chatProvider: hasChat ? { [chatProvider] in chatProvider } : nil,
            entitlements: NothingLocked()
        )
        await service.refresh()
        let assistant = AIAssistant(session: session, service: service, defaults: defaults, locale: Locale(identifier: "en_US"))
        return MapChat(session: session, assistant: assistant, locale: Locale(identifier: "en_US"))
    }

    private func node(_ title: String, in chat: MapChat) throws -> NodeID {
        try #require(chat.session.engine.state.nodes.values.first { $0.title == title }?.id)
    }

    private func citation(_ handle: String, _ title: String, in chat: MapChat) throws -> ChatCitation {
        ChatCitation(handle: handle, mapID: chat.session.map.id, nodeID: try node(title, in: chat), title: title)
    }

    private func ask(_ question: String, in chat: MapChat) async {
        chat.draft = question
        chat.ask()
        await chat.answerSettled()
    }

    // MARK: Asking

    @Test func anAnswerArrivesWithItsCitationsAndChangesNothing() async throws {
        let chat = try await open()
        let beta = try citation("T2", "Beta", in: chat)
        chatProvider.enqueue(.text("The beta comes first [T2].", citations: [beta]))

        await ask("What comes first?", in: chat)

        let entry = try #require(chat.entries.first)
        #expect(entry.question == "What comes first?")
        #expect(entry.displayAnswer == "The beta comes first.")
        #expect(entry.citations == [beta])
        #expect(entry.state == .complete)
        #expect(chat.draft.isEmpty)
        #expect(chat.turns.map(\.answer) == ["The beta comes first [T2]."])
        #expect(!chat.session.canUndo, "asking never edits the map")
        #expect(chatProvider.questions.first?.scope == .map(chat.session.map.id))
    }

    @Test func theAnswerFollowsTheLanguageOfTheQuestion() async throws {
        let chat = try await open()
        chatProvider.enqueue(.text("Bản beta đi trước.", citations: []))

        await ask("Việc nào làm trước tiên trong kế hoạch ra mắt?", in: chat)

        #expect(chatProvider.questions.first?.message.language == .vietnamese)
    }

    @Test func oneConversationHoldsEveryQuestionUntilCleared() async throws {
        let chat = try await open()
        chatProvider.enqueue(.text("One.", citations: []))
        chatProvider.enqueue(.text("Two.", citations: []))
        chatProvider.enqueue(.text("Three.", citations: []))

        await ask("First?", in: chat)
        await ask("Second?", in: chat)
        #expect(chatProvider.conversationCount == 1)
        #expect(chatProvider.questions.last?.history.map(\.question) == ["First?"])

        chat.clear()
        #expect(chat.entries.isEmpty)
        #expect(!chat.canClear)
        await ask("Third?", in: chat)
        #expect(chatProvider.conversationCount == 2)
        #expect(chatProvider.questions.last?.history.isEmpty == true)
    }

    @Test func stoppingKeepsWhatArrivedAndAllowsTheNextQuestion() async throws {
        let chat = try await open()
        chatProvider.enqueue(.hang)
        chat.draft = "Long?"
        chat.ask()
        #expect(chat.isAnswering)
        #expect(!chat.canAsk)

        chat.stop()

        #expect(!chat.isAnswering)
        #expect(chat.entries.last?.state == .stopped)
        chat.draft = "Again?"
        #expect(chat.canAsk)
    }

    @Test func aFailureSaysWhatToDoInOneLine() async throws {
        let chat = try await open()
        chatProvider.enqueue(.failure(.guardrailViolation))

        await ask("Something odd", in: chat)

        #expect(chat.entries.last?.state == .failed(.rephrase))
        #expect(!chat.isAnswering)
    }

    @Test func aLanguageTheModelLacksIsReported() async throws {
        let chat = try await open(capabilities: AICapabilities(model: .ready, supportedLanguages: [.english], contextSize: 4_096))
        chatProvider.enqueue(.text("Không dùng tới.", citations: []))

        await ask("Kế hoạch ra mắt có những bước nào?", in: chat)

        #expect(chat.entries.last?.state == .failed(.unsupportedLanguage))
    }

    @Test func theFirstQuestionWaitsForThePrivacyNotice() async throws {
        let chat = try await open()
        defaults.set(false, forKey: AIAssistant.privacyNoticeKey)
        chatProvider.enqueue(.text("Yes.", citations: []))

        chat.draft = "Anything?"
        chat.ask()
        #expect(chat.assistant.sheet == .privacyNotice)
        #expect(chat.entries.isEmpty)

        chat.assistant.acknowledgePrivacyNotice()
        await chat.answerSettled()
        #expect(chat.entries.last?.state == .complete)
    }

    // MARK: Citations

    @Test func aCitationSelectsTheTopicAndRevealsItAsOneUndoStep() async throws {
        let chat = try await open()
        let session = chat.session
        let planID = try node("Plan", in: chat)
        session.perform(UpdateNodeCommand(nodeID: planID, .isCollapsed(true)), named: "Collapse Topic")
        let beta = try citation("T2", "Beta", in: chat)

        #expect(chat.open(beta))

        #expect(session.selection == beta.nodeID)
        #expect(session.scrollRequest == beta.nodeID)
        #expect(session.engine.state.node(planID)?.isCollapsed == false)

        session.undo()
        #expect(session.engine.state.node(planID)?.isCollapsed == true)
        session.redo()
        #expect(session.engine.state.node(planID)?.isCollapsed == false)
    }

    @Test func aVisibleCitationChangesNothingButTheSelection() async throws {
        let chat = try await open()
        let budget = try citation("T3", "Budget", in: chat)

        #expect(chat.open(budget))

        #expect(chat.session.selection == budget.nodeID)
        #expect(!chat.session.canUndo)
    }

    @Test func aDeletedTopicNoLongerOpens() async throws {
        let chat = try await open()
        let budget = try citation("T3", "Budget", in: chat)
        chat.session.perform(DeleteNodeCommand(nodeID: budget.nodeID), named: "Delete Topic")

        #expect(!chat.exists(budget))
        #expect(!chat.open(budget))
        #expect(chat.title(of: budget) == "Budget")
    }

    @Test func aRenamedTopicShowsItsCurrentTitle() async throws {
        let chat = try await open()
        let budget = try citation("T3", "Budget", in: chat)
        chat.session.perform(UpdateNodeCommand(nodeID: budget.nodeID, .title("Costs")), named: "Rename Topic")

        #expect(chat.title(of: budget) == "Costs")
    }

    // MARK: Availability

    @Test func hiddenWhereAIIsHidden() async throws {
        let chat = try await open(capabilities: .notEligible)

        #expect(!chat.showsEntryPoints)
        chat.present()
        #expect(!chat.isPresented)
    }

    @Test func shownButUnableToAskWhileAppleIntelligenceIsOff() async throws {
        let chat = try await open(capabilities: AICapabilities(model: .appleIntelligenceOff))
        chat.draft = "Anything?"

        #expect(chat.showsEntryPoints)
        #expect(!chat.canAsk)
        #expect(chat.modelAvailability == .appleIntelligenceOff)
        chat.present()
        #expect(chat.isPresented)
        #expect(chat.focusRequest)
    }

    @Test func noChatWithoutALibraryToRead() async throws {
        let chat = try await open(hasChat: false)

        #expect(!chat.showsEntryPoints)
    }

    // MARK: Saved with the map (MM-55)

    /// The chat as the map's next opening builds it, from the store.
    private func reopen(_ chat: MapChat) async throws -> MapChat {
        let history = try await repository.chatTurns(for: chat.session.map.id)
        return MapChat(session: chat.session, assistant: chat.assistant, history: history, locale: Locale(identifier: "en_US"))
    }

    @Test func aFinishedTurnIsSavedAndComesBackWhenTheMapOpensAgain() async throws {
        let chat = try await open()
        let beta = try citation("T2", "Beta", in: chat)
        chatProvider.enqueue(.text("The beta comes first [T2].", citations: [beta]))
        await ask("What comes first?", in: chat)

        let reopened = try await reopen(chat)

        #expect(reopened.entries.map(\.question) == ["What comes first?"])
        #expect(reopened.entries.first?.citations == [beta])
        #expect(reopened.entries.first?.state == .complete)
        #expect(reopened.canClear)
        #expect(!chat.session.canUndo, "saving the chat is not an edit")
    }

    /// The model sees the saved turns, so a follow-up question has its context.
    @Test func theNextQuestionAfterReopeningCarriesTheSavedTurns() async throws {
        let chat = try await open()
        chatProvider.enqueue(.text("One.", citations: []))
        await ask("First?", in: chat)
        let reopened = try await reopen(chat)
        chatProvider.enqueue(.text("Two.", citations: []))

        await ask("Second?", in: reopened)

        #expect(chatProvider.questions.last?.history.map(\.question) == ["First?"])
        #expect(try await repository.chatTurns(for: chat.session.map.id).map(\.question) == ["First?", "Second?"])
    }

    @Test func clearChatAsksFirstThenDeletesTheSavedChat() async throws {
        let chat = try await open()
        chatProvider.enqueue(.text("One.", citations: []))
        await ask("First?", in: chat)

        chat.requestClear()
        #expect(chat.isConfirmingClear)
        #expect(chat.isPresented)
        #expect(chat.entries.count == 1, "nothing goes before the person confirms")

        chat.clear()
        await chat.answerSettled()
        #expect(chat.entries.isEmpty)
        #expect(try await repository.chatTurns(for: chat.session.map.id).isEmpty)
        #expect(try await reopen(chat).entries.isEmpty)
    }

    @Test func stoppedAndFailedAnswersAreNotSaved() async throws {
        let chat = try await open()
        chatProvider.enqueue(.failure(.guardrailViolation))
        await ask("Something odd", in: chat)
        chatProvider.enqueue(.hang)
        chat.draft = "Long?"
        chat.ask()
        chat.stop()
        await chat.answerSettled()

        #expect(try await repository.chatTurns(for: chat.session.map.id).isEmpty)
    }

    private struct OpenFailed: Error {}
}

/// Ask in a map is free; nothing here should ask, but the service needs an answer.
private struct NothingLocked: ProEntitlements {
    func allows(_ feature: ProFeature) -> Bool { true }
}

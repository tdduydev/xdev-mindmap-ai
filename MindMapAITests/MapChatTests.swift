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
    /// What Copy put on the pasteboard; the tests leave the real one alone.
    let copied = CopiedText()

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
        return MapChat(session: session, assistant: assistant, locale: Locale(identifier: "en_US"), copyText: { [copied] in copied.texts.append($0) })
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

    // MARK: Suggested questions and scope (MM-78)

    @Test func anEmptyChatSuggestsQuestionsAboutTheMapThatAskAtOnce() async throws {
        let chat = try await open()
        chatProvider.enqueue(.text("Plan and Budget.", citations: []))
        chat.draft = "half typed"

        #expect(chat.suggestedQuestions == ["Summarize this map", "What is missing?", "What are the next steps?"])
        chat.ask(suggestion: "Summarize this map")
        await chat.answerSettled()

        #expect(chat.entries.map(\.question) == ["Summarize this map"])
        #expect(chat.entries.first?.state == .complete)
        #expect(chat.draft == "half typed", "a suggestion leaves the draft alone")
        #expect(chatProvider.questions.first?.message.branch == nil)
    }

    @Test func aSuggestionWaitsWhileAnAnswerIsComing() async throws {
        let chat = try await open()
        chatProvider.enqueue(.hang)
        chat.ask(suggestion: "What is missing?")
        #expect(!chat.canAskSuggestion)

        chat.ask(suggestion: "What are the next steps?")
        chat.stop()

        #expect(chat.entries.map(\.question) == ["What is missing?"])
    }

    @Test func theScopeIsTheWholeMapUntilABranchIsChosen() async throws {
        let chat = try await open()
        #expect(chat.selectableBranch == nil, "the central topic is selected when the map opens")
        chat.asksAboutSelectedBranch = true
        #expect(chat.branch == nil)

        let planID = try node("Plan", in: chat)
        chat.session.selection = planID
        #expect(chat.selectableBranch == ChatBranch(nodeID: planID, title: "Plan"))
        #expect(chat.branch == nil, "selecting a topic does not change the scope by itself")

        chat.asksAboutSelectedBranch = true
        #expect(chat.branch == ChatBranch(nodeID: planID, title: "Plan"))
        #expect(chat.suggestedQuestions.first == "Summarize this branch")
    }

    @Test func deselectingGoesBackToTheWholeMap() async throws {
        let chat = try await open()
        let planID = try node("Plan", in: chat)
        chat.session.selection = planID
        chat.asksAboutSelectedBranch = true

        chat.session.selection = nil
        chat.selectionChanged()
        #expect(chat.branch == nil)
        #expect(!chat.asksAboutSelectedBranch)

        chat.session.selection = planID
        #expect(chat.branch == nil, "the old choice does not come back quietly")

        chat.asksAboutSelectedBranch = true
        chat.session.selection = try node("Budget", in: chat)
        #expect(chat.branch == nil, "another topic is another branch: back to the whole map")
    }

    @Test func aBranchQuestionCarriesTheBranchAndIsSavedWithIt() async throws {
        let chat = try await open()
        let planID = try node("Plan", in: chat)
        chat.session.selection = planID
        chat.asksAboutSelectedBranch = true
        let beta = try citation("T1", "Beta", in: chat)
        chatProvider.enqueue(.text("In the Plan branch, the beta comes first [T1].", citations: [beta]))

        await ask("What comes first?", in: chat)

        let branch = ChatBranch(nodeID: planID, title: "Plan")
        #expect(chatProvider.questions.first?.message.branch == branch)
        #expect(chat.entries.first?.branch == branch)
        #expect(chat.turns.first?.branch == branch)
        let reopened = try await reopen(chat)
        #expect(reopened.entries.first?.branch == branch, "the saved turn says which branch it covered")
    }

    @Test func theScopeIsTakenWhenTheQuestionIsAsked() async throws {
        let chat = try await open()
        defaults.set(false, forKey: AIAssistant.privacyNoticeKey)
        let planID = try node("Plan", in: chat)
        chat.session.selection = planID
        chat.asksAboutSelectedBranch = true
        chatProvider.enqueue(.text("Yes.", citations: []))

        chat.draft = "Anything?"
        chat.ask()
        chat.session.selection = nil
        chat.assistant.acknowledgePrivacyNotice()
        await chat.answerSettled()

        #expect(chatProvider.questions.first?.message.branch?.nodeID == planID)
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

    // MARK: Answer actions (MM-79)

    private func undoManager(for session: EditorSession) -> UndoManager {
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        session.undoManager = undoManager
        return undoManager
    }

    @Test func copyPutsThePlainAnswerWithoutHandles() async throws {
        let chat = try await open()
        let beta = try citation("T2", "Beta", in: chat)
        chatProvider.enqueue(.text("The beta comes first [T2].\nThen the budget [T1, T3].", citations: [beta]))
        await ask("What comes first?", in: chat)
        let entry = try #require(chat.entries.last)

        #expect(chat.canCopyLastAnswer)
        chat.copy(entry)

        #expect(copied.texts == ["The beta comes first.\nThen the budget."])
        #expect(!chat.session.canUndo, "copying never edits the map")
    }

    @Test func anUnfinishedAnswerCannotBeCopiedOrAdded() async throws {
        let chat = try await open()
        chatProvider.enqueue(.hang)
        chat.draft = "Long?"
        chat.ask()
        let entry = try #require(chat.entries.last)

        #expect(!chat.canCopy(entry))
        #expect(!chat.canAddToNote(entry))
        #expect(!chat.canAskAgain(entry), "Ask Again waits for the answer to stop")
        chat.stop()
        let stopped = try #require(chat.entries.last)
        #expect(!chat.canCopy(stopped))
        #expect(chat.canAskAgain(stopped))
    }

    @Test func addToNoteAppendsToTheSelectedTopicAsOneUndoStep() async throws {
        let chat = try await open()
        let session = chat.session
        let undoManager = undoManager(for: session)
        let planID = try node("Plan", in: chat)
        session.perform(UpdateNodeCommand(nodeID: planID, .note("Earlier note\n")), named: "Edit Note")
        session.selection = planID
        chatProvider.enqueue(.text("Start with the beta [T2].", citations: [try citation("T2", "Beta", in: chat)]))
        await ask("What first?", in: chat)
        let entry = try #require(chat.entries.last)
        #expect(chat.noteTarget(for: entry) == planID, "the selection wins over the citation")

        undoManager.beginUndoGrouping()
        #expect(chat.addToNote(entry))
        undoManager.endUndoGrouping()

        #expect(session.engine.state.node(planID)?.note == "Earlier note\n\nStart with the beta.")
        #expect(undoManager.undoActionName == String(localized: "Add Answer to Note"))

        undoManager.undo()
        #expect(session.engine.state.node(planID)?.note == "Earlier note\n")
        #expect(undoManager.redoActionName == String(localized: "Add Answer to Note"))

        undoManager.redo()
        #expect(session.engine.state.node(planID)?.note == "Earlier note\n\nStart with the beta.")

        await session.flush()
        let stored = try #require(try await repository.loadGraph(for: session.map.id))
        #expect(stored.node(planID)?.note == "Earlier note\n\nStart with the beta.")
    }

    @Test func withNothingSelectedTheFirstCitedTopicThatExistsGetsTheNote() async throws {
        let chat = try await open()
        let session = chat.session
        let budgetID = try node("Budget", in: chat)
        let gone = ChatCitation(handle: "T9", mapID: session.map.id, nodeID: NodeID(), title: "Deleted")
        chatProvider.enqueue(.text("Keep the budget small [T9][T3].", citations: [gone, try citation("T3", "Budget", in: chat)]))
        await ask("Budget?", in: chat)
        session.selection = nil
        let entry = try #require(chat.entries.last)

        let undoManager = undoManager(for: session)
        #expect(chat.noteTarget(for: entry) == budgetID)
        undoManager.beginUndoGrouping()
        #expect(chat.addToNote(entry))
        undoManager.endUndoGrouping()
        #expect(session.engine.state.node(budgetID)?.note == "Keep the budget small.")

        undoManager.undo()
        #expect(session.engine.state.node(budgetID)?.note == nil)
        undoManager.redo()
        #expect(session.engine.state.node(budgetID)?.note == "Keep the budget small.")
    }

    @Test func addToNoteNeedsOneTopic() async throws {
        let chat = try await open()
        chatProvider.enqueue(.text("No sources.", citations: []))
        await ask("Anything?", in: chat)
        chat.session.selection = nil
        let entry = try #require(chat.entries.last)

        #expect(chat.noteTarget(for: entry) == nil)
        #expect(!chat.canAddLastAnswerToNote)
        #expect(!chat.addToNote(entry))
        #expect(!chat.session.engine.canUndo)
    }

    @Test func askAgainReplacesTheLastAnswerAndItsSavedTurn() async throws {
        let chat = try await open()
        let mapID = chat.session.map.id
        chatProvider.enqueue(.text("One.", citations: []))
        chatProvider.enqueue(.text("Two.", citations: []))
        chatProvider.enqueue(.text("Two, better.", citations: []))
        await ask("First?", in: chat)
        await ask("Second?", in: chat)
        let first = try #require(chat.entries.first)
        #expect(!chat.canAskAgain(first), "only the last question can be asked again")

        chat.askLastQuestionAgain()
        await chat.answerSettled()

        #expect(chat.entries.map(\.question) == ["First?", "Second?"])
        #expect(chat.entries.map(\.displayAnswer) == ["One.", "Two, better."])
        #expect(chatProvider.questions.last?.message.text == "Second?")
        #expect(chatProvider.questions.last?.history.map(\.answer) == ["One."], "the model does not see the answer it replaces")
        let saved = try await repository.chatTurns(for: mapID)
        #expect(saved.map(\.answer) == ["One.", "Two, better."])
    }

    @Test func askAgainKeepsTheBranchOfTheQuestion() async throws {
        let chat = try await open()
        let planID = try node("Plan", in: chat)
        chat.session.selection = planID
        chat.asksAboutSelectedBranch = true
        chatProvider.enqueue(.text("Beta.", citations: []))
        chatProvider.enqueue(.text("Beta again.", citations: []))
        await ask("What is here?", in: chat)
        chat.session.selection = nil

        chat.askLastQuestionAgain()
        await chat.answerSettled()

        #expect(chatProvider.questions.last?.message.branch?.nodeID == planID)
        #expect(chat.entries.last?.branch?.nodeID == planID)
    }

    @Test func aFailedRetryLeavesNoStaleAnswerSaved() async throws {
        let chat = try await open()
        chatProvider.enqueue(.text("One.", citations: []))
        chatProvider.enqueue(.failure(.guardrailViolation))
        await ask("First?", in: chat)

        chat.askLastQuestionAgain()
        await chat.answerSettled()

        #expect(chat.entries.last?.state == .failed(.rephrase))
        #expect(try await repository.chatTurns(for: chat.session.map.id).isEmpty)
        #expect(chat.canAskLastQuestionAgain, "a failed retry can be asked again")
    }

    private struct OpenFailed: Error {}
}

/// What Copy wrote, in place of the pasteboard.
final class CopiedText {
    var texts: [String] = []
}

/// Ask in a map is free; nothing here should ask, but the service needs an answer.
private struct NothingLocked: ProEntitlements {
    func allows(_ feature: ProFeature) -> Bool { true }
}

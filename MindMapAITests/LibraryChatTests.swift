import Foundation
@testable import MindMapAI
import MindMapAICore
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import MindMapTestSupport
import Testing

/// Ask across the library (MM-52) without a model: `MockChatProvider` answers.
/// Pro is checked before the panel opens and before each question.
@Suite("Library chat")
struct LibraryChatTests {
    let chatProvider = MockChatProvider()
    let defaults: UserDefaults
    let copied = CopiedText()
    let opened = OpenedTopics()

    init() throws {
        defaults = try #require(UserDefaults(suiteName: "LibraryChatTests.\(UUID().uuidString)"))
        defaults.set(true, forKey: AIAssistant.privacyNoticeKey)
    }

    private func makeChat(pro: Bool = true, capabilities: AICapabilities = .readyForTesting, topicExists: Bool = true) async -> LibraryChat {
        let aiProvider = MockAIProvider(capabilities: capabilities)
        chatProvider.setCapabilities(capabilities)
        let service = AIService(
            provider: { aiProvider },
            chatProvider: { [chatProvider] in chatProvider },
            entitlements: Entitlements(askLibrary: pro)
        )
        await service.refresh()
        return LibraryChat(
            service: service,
            defaults: defaults,
            locale: Locale(identifier: "en_US"),
            copyText: { [copied] in copied.texts.append($0) },
            openTopic: { [opened] citation in
                opened.citations.append(citation)
                return topicExists
            }
        )
    }

    private func ask(_ question: String, in chat: LibraryChat) async {
        chat.draft = question
        chat.ask()
        await chat.answerSettled()
    }

    private let launch = ChatCitation(handle: "T1", mapID: MapID(), nodeID: NodeID(), title: "Launch")
    private let budget = ChatCitation(handle: "T2", mapID: MapID(), nodeID: NodeID(), title: "Budget")

    // MARK: Pro

    @Test func withoutProThePanelStaysClosedAndThePaywallOpens() async {
        let chat = await makeChat(pro: false)

        chat.present()

        #expect(!chat.isPresented)
        #expect(chat.paywall?.feature == .askLibrary)
    }

    @Test func withoutProAQuestionIsNotSent() async {
        let chat = await makeChat(pro: false)

        await ask("What are my maps about?", in: chat)

        #expect(chatProvider.questions.isEmpty)
        #expect(chat.entries.isEmpty)
        #expect(chat.paywall?.feature == .askLibrary)
    }

    @Test func withProThePanelOpensFocused() async {
        let chat = await makeChat()

        chat.present()

        #expect(chat.isPresented)
        #expect(chat.focusRequest)
        #expect(chat.paywall == nil)
        chat.toggle()
        #expect(!chat.isPresented)
    }

    @Test func askLibraryIsAnAIProFeature() {
        #expect(ProFeature.askLibrary.needsOnDeviceModel)
        #expect(!ProFeature.offered(includingAI: false).contains(.askLibrary))
    }

    // MARK: Asking

    @Test func aQuestionReadsTheWholeLibraryWithCitationsFromSeveralMaps() async throws {
        let chat = await makeChat()
        chatProvider.enqueue(.text("Launch [T1] and budget [T2].", citations: [launch, budget]))

        await ask("What are my maps about?", in: chat)

        let entry = try #require(chat.entries.first)
        #expect(entry.displayAnswer == "Launch and budget.")
        #expect(entry.citations == [launch, budget])
        #expect(entry.state == .complete)
        #expect(chatProvider.questions.first?.scope == .library)
        #expect(chatProvider.questions.first?.message.branch == nil)
        #expect(chat.draft.isEmpty)
    }

    @Test func oneConversationUntilCleared() async {
        let chat = await makeChat()
        chatProvider.enqueue(.text("One.", citations: []))
        chatProvider.enqueue(.text("Two.", citations: []))
        chatProvider.enqueue(.text("Three.", citations: []))

        await ask("First?", in: chat)
        await ask("Second?", in: chat)
        #expect(chatProvider.conversationCount == 1)
        #expect(chatProvider.questions.last?.history.map(\.question) == ["First?"])

        chat.clear()
        #expect(chat.entries.isEmpty)
        await ask("Third?", in: chat)
        #expect(chatProvider.conversationCount == 2)
        #expect(chatProvider.questions.last?.history.isEmpty == true)
    }

    @Test func aVietnameseQuestionGetsAVietnameseAnswer() async {
        let chat = await makeChat()
        chatProvider.enqueue(.text("Ngân sách.", citations: []))

        await ask("Sơ đồ nào nói về ngân sách năm sau?", in: chat)

        #expect(chatProvider.questions.first?.message.language == .vietnamese)
    }

    @Test func aSuggestedQuestionIsAskedAndLeavesTheDraft() async {
        let chat = await makeChat()
        chatProvider.enqueue(.text("Two maps.", citations: []))
        chat.draft = "half typed"

        chat.ask(suggestion: chat.suggestedQuestions[0])
        await chat.answerSettled()

        #expect(chatProvider.questions.first?.message.text == "What are my maps about?")
        #expect(chat.draft == "half typed")
    }

    @Test func stoppingKeepsTheQuestionAndAllowsAnother() async {
        let chat = await makeChat()
        chatProvider.enqueue(.hang)
        chat.draft = "Long?"
        chat.ask()
        #expect(chat.isAnswering)

        chat.stop()

        #expect(!chat.isAnswering)
        #expect(chat.entries.last?.state == .stopped)
        #expect(chat.canAskLastQuestionAgain)
    }

    @Test func aFailureSaysWhyInOneLine() async {
        let chat = await makeChat()
        chatProvider.enqueue(.failure(.guardrailViolation))

        await ask("Anything?", in: chat)

        #expect(chat.entries.last?.state == .failed(.rephrase))
    }

    @Test func hiddenWhereAIIsHidden() async {
        let chat = await makeChat(capabilities: AICapabilities(model: .deviceNotEligible, supportedLanguages: [], contextSize: nil))

        chat.present()

        #expect(!chat.showsEntryPoints)
        #expect(!chat.isPresented)
        #expect(chat.paywall == nil)
    }

    @Test func askAgainReplacesTheLastAnswer() async throws {
        let chat = await makeChat()
        chatProvider.enqueue(.text("First answer.", citations: []))
        chatProvider.enqueue(.text("Second answer.", citations: []))
        await ask("Which maps?", in: chat)

        chat.askLastQuestionAgain()
        await chat.answerSettled()

        #expect(chat.entries.map(\.answer) == ["Second answer."])
        #expect(chatProvider.questions.last?.history.isEmpty == true, "the model does not see the answer it replaces")
    }

    @Test func copyLeavesTheHandlesOut() async {
        let chat = await makeChat()
        chatProvider.enqueue(.text("Launch [T1].", citations: [launch]))
        await ask("Which maps?", in: chat)

        chat.copyLastAnswer()

        #expect(copied.texts == ["Launch."])
    }

    // MARK: Citations

    @Test func aCitationOpensItsMapAtTheTopic() async {
        let chat = await makeChat()

        chat.open(budget)
        await chat.answerSettled()

        #expect(opened.citations == [budget])
        #expect(chat.exists(budget))
    }

    @Test func aTopicGoneSinceIsMarked() async {
        let chat = await makeChat(topicExists: false)

        chat.open(launch)
        await chat.answerSettled()

        #expect(!chat.exists(launch))
        #expect(chat.exists(budget))
    }

    // MARK: Privacy notice

    @Test func theFirstQuestionWaitsForTheOnDeviceNotice() async throws {
        let chat = await makeChat()
        defaults.set(false, forKey: AIAssistant.privacyNoticeKey)
        chatProvider.enqueue(.text("Two maps.", citations: []))

        chat.draft = "Which maps?"
        chat.ask()
        #expect(chat.isShowingPrivacyNotice)
        #expect(chatProvider.questions.isEmpty)

        chat.acknowledgePrivacyNotice()
        await chat.answerSettled()

        #expect(!chat.isShowingPrivacyNotice)
        #expect(chatProvider.questions.count == 1)
        #expect(defaults.bool(forKey: AIAssistant.privacyNoticeKey))
    }
}

/// A library chat citation shows its topic once the map opens (MM-52).
@Suite("Open maps: library citations")
struct OpenMapsShowTopicTests {
    @Test func aTopicAskedForBeforeTheMapOpensIsSelectedWhenItOpens() async throws {
        let repository = try PersistenceController.makeRepository(at: .inMemory)
        let openMaps = OpenMaps(repository: repository, clipboard: MemoryClipboard())
        var engine = try GraphEngine(state: GraphState.newMap(title: "Plan"))
        let rootID = try #require(engine.state.map.rootNodeID)
        let collapsed = NodeID()
        let hidden = NodeID()
        try engine.execute(AddNodeCommand(nodeID: collapsed, .child(of: rootID), title: "Later"))
        try engine.execute(AddNodeCommand(nodeID: hidden, .child(of: collapsed), title: "Hidden"))
        try engine.execute(UpdateNodeCommand(nodeID: collapsed, .isCollapsed(true)))
        try await repository.create(engine.state)
        let service = AIService(provider: { MockAIProvider() }, entitlements: Entitlements(askLibrary: true))

        openMaps.showTopic(hidden, in: engine.state.map.id)
        guard case .ready(let map) = await openMaps.open(engine.state.map.id, in: WindowToken(), service: service) else {
            Issue.record("the map did not open")
            return
        }

        #expect(map.session.selection == hidden)
        #expect(!RevealNodeCommand.isHidden(hidden, in: map.session.engine.state))

        // Once open, the next citation shows at once.
        openMaps.showTopic(collapsed, in: engine.state.map.id)
        #expect(map.session.selection == collapsed)
    }
}

/// What the library chat asked to open, in place of the windows.
final class OpenedTopics {
    var citations: [ChatCitation] = []
}

private struct Entitlements: ProEntitlements {
    let askLibrary: Bool

    func allows(_ feature: ProFeature) -> Bool {
        feature == .askLibrary ? askLibrary : true
    }
}

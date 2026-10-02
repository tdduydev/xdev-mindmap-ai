import Foundation
@testable import MindMapAIApple
import MindMapAICore
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import MindMapQuery
import MindMapTestSupport
import Testing

/// What the chat's tools hand the model, read from a real store; no model needed.
@Suite("Chat map reader")
struct ChatMapReaderTests {
    let fixture: OutlineFixture
    let repository: SwiftDataMapRepository
    let reader: ChatMapReader

    init() async throws {
        var fixture = try OutlineFixture("""
        Ra mắt sản phẩm
          Kế hoạch
            Beta
            Báo chí
          Ngân sách
        """, mapTitle: "Ra mắt")
        try fixture.engine.execute(UpdateNodeCommand(nodeID: fixture["Kế hoạch"], .note("Mở beta vào tháng 5, sau đó gửi thông cáo.")))
        self.fixture = fixture
        repository = try PersistenceController.makeRepository(at: .inMemory)
        try await repository.create(fixture.state)
        let queries = MapQueries(repository: repository, graphs: RepositoryGraphSource(repository: repository))
        reader = ChatMapReader(queries: queries, mapID: fixture.state.map.id, toolOutput: 600)
    }

    @Test func searchNamesTopicsByHandleFoldingVietnameseMarks() async {
        let output = await reader.searchTopics("ke hoach")

        #expect(output.contains("- T1: Kế hoạch (under Ra mắt sản phẩm)"))
        #expect(reader.citationTable.citation(for: "T1")?.nodeID == fixture["Kế hoạch"])
        #expect(!output.contains(fixture["Kế hoạch"].description))
    }

    @Test func aSearchWithNoHitsSaysSo() async {
        let output = await reader.searchTopics("marketing")

        #expect(output.hasPrefix("No topic matches"))
        #expect(reader.citationTable.isEmpty)
    }

    @Test func readingATopicGivesItsNoteAndSubtopicsWithHandles() async {
        _ = await reader.searchTopics("kế hoạch")
        let output = await reader.readTopic("t1")

        #expect(output.hasPrefix("T1: Kế hoạch"))
        #expect(output.contains("Subtopics: T3 Beta; T4 Báo chí"))
        #expect(output.contains("Note: Mở beta vào tháng 5"))
    }

    @Test func aHandleNoToolReturnedIsNotRead() async {
        let output = await reader.readTopic("T9")

        #expect(output == ChatMapReader.unknownHandle("T9"))
    }

    @Test func aBranchWithAnEmptyHandleStartsAtTheCentralTopic() async {
        let output = await reader.readBranch("", depth: 1)

        #expect(output.contains("Map: Ra mắt"))
        #expect(output.contains("- T1: Ra mắt sản phẩm"))
        #expect(output.contains("  - T2: Kế hoạch"))
        #expect(output.contains("(2 topics deeper down"))
    }

    @Test func aDeletedTopicSaysItIsGone() async throws {
        _ = await reader.searchTopics("ngân sách")
        var engine = fixture.engine
        let changes = try engine.execute(DeleteNodeCommand(nodeID: fixture["Ngân sách"]))
        try await repository.save(changes, map: engine.state.map)

        #expect(await reader.readTopic("T1") == "Topic T1 no longer exists.")
    }

    @Test func outputStaysWithinTheBudget() async throws {
        let fixture = try OutlineFixture("Root\n" + (1...60).map { "  Chủ đề số \($0) có tiêu đề khá dài" }.joined(separator: "\n"))
        try await repository.create(fixture.state)
        let queries = MapQueries(repository: repository, graphs: RepositoryGraphSource(repository: repository))
        let small = ChatMapReader(queries: queries, mapID: fixture.state.map.id, toolOutput: 200)

        let output = await small.readBranch("", depth: 1)

        #expect(TokenEstimator.estimate(output) <= 200)
        #expect(output.contains("more topics not shown"))
    }
}

@Suite("Chat prompts")
struct ChatPromptTests {
    let catalog = PromptCatalog(version: .v26_0)

    @Test func instructionsHoldNoMapContentAndAskForCitations() {
        let instructions = catalog.chatInstructions(userLocaleIdentifier: "vi_VN")

        #expect(instructions.contains("[T1]"))
        #expect(instructions.contains("Only cite handles a tool returned."))
        #expect(instructions.hasSuffix("The person's locale is vi_VN."))
        #expect(TokenEstimator.estimate(instructions) < ChatBudget.instructionsReserve / 2)
    }

    @Test func thePromptCarriesTheQuestionAndItsLanguage() {
        let prompt = catalog.chatPrompt(question: "Khi nào ra mắt?", mapTitle: "Ra mắt", language: .vietnamese)

        #expect(prompt == "Map: Ra mắt\nQuestion: Khi nào ra mắt?\nYou MUST respond in Vietnamese.")
    }

    @Test func everyModelGenerationHasChatInstructions() {
        for version in PromptVersion.allCases {
            #expect(!PromptCatalog(version: version).chatInstructions(userLocaleIdentifier: "en_US").isEmpty)
        }
    }
}

/// The real model, only where it is ready (never in an x86_64 build): the
/// session, tools and transcript work together and citations resolve. Answer
/// quality is for the evaluations (MM-53), not for this test.
@Suite("Apple chat provider", .enabled(if: AppleCapabilityProbe.current().model == .ready), .timeLimit(.minutes(2)))
struct AppleChatProviderTests {
    @Test func answersFromTheMapAndCitesOnlyWhatToolsReturned() async throws {
        let fixture = try OutlineFixture("""
        Product launch
          Beta
            Invite fifty testers
          Press release
        """, mapTitle: "Product launch")
        let repository = try PersistenceController.makeRepository(at: .inMemory)
        try await repository.create(fixture.state)
        let provider = AppleChatProvider(queries: MapQueries(repository: repository, graphs: RepositoryGraphSource(repository: repository)))
        let conversation = provider.conversation(in: .map(fixture.state.map.id), history: [])
        let message = ChatMessage(text: "How many testers will the beta invite?", language: .english, userLocaleIdentifier: "en_US")

        var last: ChatUpdate?
        for try await update in conversation.send(message) { last = update }

        let answer = try #require(last)
        #expect(answer.isComplete)
        #expect(!answer.text.isEmpty)
        let known = Set([fixture["Product launch"], fixture["Beta"], fixture["Invite fifty testers"], fixture["Press release"]])
        #expect(answer.citations.allSatisfy { known.contains($0.nodeID) })

        // A second question in the same conversation still answers.
        var second: ChatUpdate?
        for try await update in conversation.send(ChatMessage(text: "What else is planned?", language: .english, userLocaleIdentifier: "en_US")) {
            second = update
        }
        #expect(second?.isComplete == true)
    }
}

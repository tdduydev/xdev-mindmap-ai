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

    // MARK: Branch scope (MM-78)

    @Test func aBranchQuestionSearchesOnlyInsideTheBranch() async {
        reader.setBranch(fixture["Kế hoạch"])

        let inside = await reader.searchTopics("beta")
        let outside = await reader.searchTopics("ngân sách")

        #expect(inside.contains(": Beta"))
        #expect(outside.hasPrefix("No topic matches"))
        #expect(outside.contains("the whole branch"))
        let cited = Set(reader.citationTable.citations(in: "[T1] [T2] [T3]").map(\.nodeID))
        let branch: Set<NodeID> = [fixture["Kế hoạch"], fixture["Beta"], fixture["Báo chí"]]
        #expect(!cited.isEmpty && cited.isSubset(of: branch), "every handle handed out lies in the branch")
    }

    @Test func aHandleFromOutsideTheBranchIsNotRead() async {
        _ = await reader.searchTopics("ngân sách")
        reader.setBranch(fixture["Kế hoạch"])

        #expect(await reader.readTopic("T1") == ChatMapReader.outsideBranch("T1"))
        #expect(await reader.readBranch("T1", depth: 1) == ChatMapReader.outsideBranch("T1"))
    }

    @Test func anEmptyHandleReadsFromTheBranchTopic() async {
        reader.setBranch(fixture["Kế hoạch"])

        let output = await reader.readBranch("", depth: 2)

        #expect(output.contains("- T1: Kế hoạch"))
        #expect(output.contains("Beta"))
        #expect(!output.contains("Ngân sách"))
        #expect(!output.contains("Ra mắt sản phẩm"))
    }

    @Test func aTopicInsideTheBranchReadsAsUsual() async {
        reader.setBranch(fixture["Kế hoạch"])
        _ = await reader.searchTopics("beta")

        #expect(await reader.readTopic("T1").hasPrefix("T1: Beta"))
    }

    @Test func clearingTheBranchReadsTheWholeMapAgain() async {
        reader.setBranch(fixture["Kế hoạch"])
        reader.setBranch(nil)

        #expect(await reader.searchTopics("ngân sách").contains(": Ngân sách"))
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

    // MARK: suggestTopics (MM-51)

    @Test func suggestingTopicsRecordsThemAndSaysNothingWasAdded() async throws {
        _ = await reader.searchTopics("kế hoạch")
        let output = await reader.suggestTopics(under: "T1", titles: ["Rủi ro", " Beta ", "Đối tác", "rủi ro", ""])

        let suggestion = try #require(reader.currentSuggestion)
        #expect(suggestion.parentID == fixture["Kế hoạch"])
        #expect(suggestion.parentTitle == "Kế hoạch")
        // Beta is already a subtopic; the repeat and the empty title are dropped.
        #expect(suggestion.topics.map(\.title) == ["Rủi ro", "Đối tác"])
        #expect(output.hasPrefix("Suggested 2 topics under T1 \u{201C}Kế hoạch\u{201D}: Rủi ro; Đối tác."))
        #expect(output.contains("Nothing was added yet"))
        // The map is untouched: only the person's Accept adds topics.
        let saved = try #require(try await repository.loadGraph(for: fixture.state.map.id))
        #expect(saved.childIDs(of: fixture["Kế hoạch"]).count == 2)
    }

    @Test func anEmptyHandleSuggestsUnderTheCentralTopicOrTheBranch() async throws {
        _ = await reader.suggestTopics(under: "", titles: ["Đội ngũ"])
        #expect(reader.currentSuggestion?.parentID == fixture["Ra mắt sản phẩm"])

        reader.setBranch(fixture["Kế hoạch"])
        _ = await reader.suggestTopics(under: "", titles: ["Rủi ro"])
        #expect(reader.currentSuggestion?.parentID == fixture["Kế hoạch"])
    }

    @Test func suggestionsOutsideTheBranchOrUnderUnknownHandlesAreRefused() async {
        _ = await reader.searchTopics("ngân sách")
        reader.setBranch(fixture["Kế hoạch"])

        #expect(await reader.suggestTopics(under: "T1", titles: ["Quỹ"]) == ChatMapReader.outsideBranch("T1"))
        #expect(await reader.suggestTopics(under: "T7", titles: ["Quỹ"]) == ChatMapReader.unknownHandle("T7"))
        #expect(reader.currentSuggestion == nil)
    }

    @Test func titlesThatAreAllPresentSuggestNothing() async {
        _ = await reader.searchTopics("kế hoạch")
        let output = await reader.suggestTopics(under: "T1", titles: ["Beta", "BÁO CHÍ"])

        #expect(output.hasPrefix("No topic was suggested"))
        #expect(reader.currentSuggestion == nil)
    }

    @Test func clearingForTheNextQuestionDropsTheSuggestion() async {
        _ = await reader.suggestTopics(under: "", titles: ["Đội ngũ"])
        reader.clearSuggestion()

        #expect(reader.currentSuggestion == nil)
    }
}

/// Ask across the library (C3): the reader with no map reads every live map.
@Suite("Chat library reader")
struct ChatLibraryReaderTests {
    let launch: OutlineFixture
    let budget: OutlineFixture
    let repository: SwiftDataMapRepository
    let reader: ChatMapReader

    init() async throws {
        launch = try OutlineFixture("""
        Ra mắt sản phẩm
          Kế hoạch
            Beta
        """, mapTitle: "Ra mắt")
        budget = try OutlineFixture("""
        Ngân sách 2027
          Kế hoạch chi
          Thuê ngoài
        """, mapTitle: "Ngân sách")
        repository = try PersistenceController.makeRepository(at: .inMemory)
        try await repository.create(launch.state)
        try await repository.create(budget.state)
        let queries = MapQueries(repository: repository, graphs: RepositoryGraphSource(repository: repository))
        reader = ChatMapReader(queries: queries, mapID: nil, toolOutput: 600)
    }

    @Test func listMapsNamesEveryLiveMapByHandle() async throws {
        try await repository.moveToRecentlyDeleted(budget.state.map.id, at: .now)

        let output = await reader.listMaps("")

        #expect(output.contains("- M1: Ra mắt (3 topics)"))
        #expect(!output.contains("Ngân sách"), "Recently Deleted is never listed")
        #expect(reader.map(for: "m1") == launch.state.map.id)
        #expect(reader.map(for: "M2") == nil)
    }

    @Test func listMapsMatchesTitlesFoldingMarks() async {
        let output = await reader.listMaps("ngan sach")

        #expect(output.contains(": Ngân sách"))
        #expect(!output.contains("Ra mắt"))
    }

    @Test func searchFindsTopicsInEveryMapAndSaysWhichMap() async {
        let output = await reader.searchTopics("ke hoach")

        #expect(output.contains("Kế hoạch (map M"))
        #expect(output.contains("Kế hoạch chi (map M"))
        let maps = Set(reader.citationTable.citations(in: "[T1] [T2]").map(\.mapID))
        #expect(maps == [launch.state.map.id, budget.state.map.id])
        #expect(!output.contains(launch.state.map.id.description))
    }

    @Test func aMapHandleReadsTheWholeMap() async {
        _ = await reader.listMaps("ngân")

        let output = await reader.readBranch("M1", depth: 1)

        #expect(output.hasPrefix("Map M1: Ngân sách"))
        #expect(output.contains("- T1: Ngân sách 2027"))
        #expect(output.contains("  - T2: Kế hoạch chi"))
        #expect(reader.citationTable.citation(for: "T2")?.mapID == budget.state.map.id)
    }

    @Test func aTopicHandleReadsInItsOwnMap() async {
        _ = await reader.searchTopics("beta")

        let topic = await reader.readTopic("T1")
        let branch = await reader.readBranch("T1", depth: 1)

        #expect(topic.hasPrefix("T1: Beta"))
        #expect(topic.contains("Path: T2 Ra mắt sản phẩm > T3 Kế hoạch"))
        #expect(branch.contains("Ra mắt"))
        #expect(reader.citationTable.citation(for: "T3")?.mapID == launch.state.map.id)
    }

    @Test func anEmptyOrUnknownHandleAsksForAMap() async {
        #expect(await reader.readBranch("", depth: 1).hasPrefix("Give the handle of a map"))
        #expect(await reader.readBranch("M4", depth: 1) == ChatMapReader.unknownHandle("M4"))
    }

    @Test func noHitsPointsToListMaps() async {
        let output = await reader.searchTopics("marketing")

        #expect(output.hasPrefix("No topic in any map matches"))
        #expect(output.contains("listMaps"))
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

    @Test func instructionsSaySuggestedTopicsAreOnlySuggested() {
        let instructions = catalog.chatInstructions(userLocaleIdentifier: "en_US")

        #expect(instructions.contains("call suggestTopics"))
        #expect(instructions.contains("never say they were added"))
    }

    @Test func thePromptCarriesTheQuestionAndItsLanguage() {
        let prompt = catalog.chatPrompt(question: "Khi nào ra mắt?", mapTitle: "Ra mắt", language: .vietnamese)

        #expect(prompt == "Map: Ra mắt\nQuestion: Khi nào ra mắt?\nYou MUST respond in Vietnamese.")
    }

    @Test func aBranchQuestionSaysWhichBranchTheToolsRead() {
        let prompt = catalog.chatPrompt(question: "Còn thiếu gì?", mapTitle: "Ra mắt", language: .vietnamese, branchTitle: "Kế\nhoạch")

        #expect(prompt.contains("Scope: only the branch \u{201C}Kế hoạch\u{201D}."))
        #expect(prompt.contains("saying it covers this branch"))
        #expect(prompt.hasSuffix("Question: Còn thiếu gì?\nYou MUST respond in Vietnamese."))
    }

    @Test func libraryInstructionsNameListMapsAndFitTheReserve() {
        let instructions = catalog.libraryChatInstructions(userLocaleIdentifier: "vi_VN")

        #expect(instructions.contains("listMaps"))
        #expect(instructions.contains("[T1]"))
        #expect(instructions.hasSuffix("The person's locale is vi_VN."))
        #expect(TokenEstimator.estimate(instructions) < ChatBudget.instructionsReserve / 2)
    }

    @Test func aLibraryPromptHasNoMapTitle() {
        let prompt = catalog.libraryChatPrompt(question: "Map nào nói về ngân sách?", language: .vietnamese)

        #expect(prompt == "Scope: every map in the library.\nQuestion: Map nào nói về ngân sách?\nYou MUST respond in Vietnamese.")
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

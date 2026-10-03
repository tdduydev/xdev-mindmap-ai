import Foundation
import MindMapAICore
import MindMapDomain
import MindMapTestSupport
import Testing

@Suite("Citation table")
struct CitationTableTests {
    let mapID = MapID()

    @Test func aTopicKeepsItsHandleAndNewTopicsGetTheNextNumber() {
        var table = CitationTable()
        let launch = NodeID()
        let budget = NodeID()

        #expect(table.handle(for: launch, in: mapID, title: "Launch") == "T1")
        #expect(table.handle(for: budget, in: mapID, title: "Budget") == "T2")
        #expect(table.handle(for: launch, in: mapID, title: "Launch plan") == "T1")
        #expect(table.citation(for: "T1")?.title == "Launch plan")
    }

    @Test func onlyHandlesAToolReturnedBecomeCitations() {
        var table = CitationTable()
        let launch = NodeID()
        _ = table.handle(for: launch, in: mapID, title: "Launch")

        let citations = table.citations(in: "Launch is in May [T1]. The budget is unknown [T7].")

        #expect(citations == [ChatCitation(handle: "T1", mapID: mapID, nodeID: launch, title: "Launch")])
    }

    @Test func readsGroupedHandlesOnceEachInOrderWhateverTheCase() {
        var table = CitationTable()
        let first = NodeID()
        let second = NodeID()
        _ = table.handle(for: first, in: mapID, title: "A")
        _ = table.handle(for: second, in: mapID, title: "B")

        let citations = table.citations(in: "Both [T2, t1]. Again [T 1].")

        #expect(citations.map(\.handle) == ["T2", "T1"])
    }

    @Test func theDisplayTextDropsHandlesAndAHalfWrittenOne() {
        #expect(CitationTable.displayText("Launch is in May [T1]. Budget [T2; T3] is set.") == "Launch is in May. Budget is set.")
        #expect(CitationTable.displayText("Kế hoạch ra mắt [T") == "Kế hoạch ra mắt")
        #expect(CitationTable.displayText("Use [brackets] as written") == "Use [brackets] as written")
    }

    // MARK: Library (C3)

    @Test func theSameNodeIDInTwoMapsGetsTwoHandles() {
        var table = CitationTable()
        let shared = NodeID()
        let otherMap = MapID()

        #expect(table.handle(for: shared, in: mapID, title: "Launch") == "T1")
        #expect(table.handle(for: shared, in: otherMap, title: "Launch copy") == "T2")
        #expect(table.citation(for: "T2")?.mapID == otherMap)
    }

    @Test func mapHandlesAreShownNeverCited() {
        var table = CitationTable()
        let launch = NodeID()
        _ = table.handle(for: launch, in: mapID, title: "Launch")

        #expect(table.citations(in: "In two maps [M1, T1].").map(\.handle) == ["T1"])
        #expect(CitationTable.displayText("In the map Launch [M2]. Kế hoạch [M") == "In the map Launch. Kế hoạch")
    }

    @Test func historyKeepsItsHandlesAndNumberingGoesOn() {
        let old = NodeID()
        let turn = ChatTurn(
            question: "When?",
            answer: "In May [T4].",
            citations: [ChatCitation(handle: "T4", mapID: mapID, nodeID: old, title: "Launch")]
        )
        var table = CitationTable(history: [turn])

        #expect(table.citation(for: "T4")?.nodeID == old)
        #expect(table.handle(for: old, in: mapID, title: "Launch") == "T4")
        #expect(table.handle(for: NodeID(), in: mapID, title: "New") == "T5")
        #expect(turn.displayAnswer == "In May.")
    }
}

@Suite("Chat budget")
struct ChatBudgetTests {
    @Test func theDevelopmentMacsWindowLeavesRoomForEarlierTurns() {
        let budget = ChatBudget(contextSize: 4_096)

        #expect(budget.toolOutput == 585)
        #expect(budget.historyAllowance(question: 30) == 4_096 - 700 - 600 - 2 * 585 - 30)
        #expect(budget.fits(used: 700, question: 30))
        #expect(!budget.fits(used: 3_000, question: 30))
    }

    @Test func aSmallWindowStillGivesToolsSomeRoom() {
        #expect(ChatBudget(contextSize: 512).toolOutput == 150)
        #expect(ChatBudget(contextSize: 8_192).toolOutput == ChatBudget.toolOutputLimit)
        #expect(ChatBudget(contextSize: 512).historyAllowance(question: 100) == 0)
    }

    @Test func keepsTheLatestTurnsThatFitWithoutAGap() {
        // Oldest first: the 500 turn does not fit after the last two, so the
        // small first turn is left out too.
        #expect(ChatBudget.latestTurnsFitting([10, 500, 100, 100], within: 300) == 2)
        #expect(ChatBudget.latestTurnsFitting([10, 20], within: 300) == 2)
        #expect(ChatBudget.latestTurnsFitting([400], within: 300) == 0)
    }
}

@Suite("Mock chat provider")
struct MockChatProviderTests {
    @Test func streamsTheScriptedAnswerAndRecordsTheQuestion() async throws {
        let provider = MockChatProvider()
        let mapID = MapID()
        let citation = ChatCitation(handle: "T1", mapID: mapID, nodeID: NodeID(), title: "Launch")
        provider.enqueue(.text("In May [T1].", citations: [citation]))
        let conversation = provider.conversation(in: .map(mapID), history: [])

        var last: ChatUpdate?
        for try await update in conversation.send(ChatMessage(text: "When?", language: .english, userLocaleIdentifier: "en_US")) {
            last = update
        }

        #expect(last == ChatUpdate(text: "In May [T1].", citations: [citation], isComplete: true))
        #expect(provider.questions.map(\.message.text) == ["When?"])
    }

    @Test func refusesALanguageTheModelDoesNotSupport() async {
        let provider = MockChatProvider(capabilities: AICapabilities(model: .ready, supportedLanguages: [.english], contextSize: 4_096))
        provider.enqueue(.text("Có", citations: []))
        let conversation = provider.conversation(in: .map(MapID()), history: [])

        await #expect(throws: AIError.unavailable(.languageUnsupported)) {
            for try await _ in conversation.send(ChatMessage(text: "Khi nào?", language: .vietnamese, userLocaleIdentifier: "vi_VN")) {}
        }
    }
}

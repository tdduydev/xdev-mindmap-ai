import Foundation
import MindMapAICore
import MindMapDomain
import MindMapGraph
import MindMapTestSupport
import Testing

/// Topics from the chat (MM-51): from the model's titles or read from an answer.
struct ChatSuggestionTests {
    let parent = NodeID()

    private func titles(_ suggestion: ChatSuggestion?) -> [String] {
        suggestion?.topics.map(\.title) ?? []
    }

    private func parents(_ suggestion: ChatSuggestion?) -> [String?] {
        suggestion?.topics.map(\.parentTemporaryID) ?? []
    }

    // MARK: From the tool

    @Test func titlesAreTrimmedDeduplicatedAndCapped() {
        let many = (1...12).map { "Idea \($0)" }
        let suggestion = ChatSuggestion(titles: ["  Risks ", "risks", "", "Line\nbreak"] + many, under: parent, parentTitle: "Launch")

        #expect(titles(suggestion).prefix(2) == ["Risks", "Line break"])
        #expect(suggestion?.topics.count == ChatSuggestion.maximumTopics)
        #expect(suggestion?.topics.map(\.temporaryID).first == "c1")
        #expect(suggestion?.proposal.feature == .chat)
        #expect(suggestion?.proposal.anchor == .node(parent))
    }

    @Test func titlesAlreadyUnderTheParentAreLeftOut() {
        let suggestion = ChatSuggestion(titles: ["Beta", "Press"], under: parent, parentTitle: "Plan", existingTitles: ["BETA"])

        #expect(titles(suggestion) == ["Press"])
        #expect(ChatSuggestion(titles: ["beta"], under: parent, parentTitle: "Plan", existingTitles: ["Beta"]) == nil)
    }

    // MARK: From an answer

    @Test func listItemsBecomeTopicsAndIndentedOnesSubtopics() {
        let answer = """
        Here is a plan [T2]:
        - **Research** the market
          - Interview users
          * Read reports [T3]
        2. Build
        3) `Launch`
        Check the cited topics.
        """
        let suggestion = ChatSuggestion(answer: answer, under: parent, parentTitle: "Plan")

        #expect(titles(suggestion) == ["Research the market", "Interview users", "Read reports", "Build", "Launch"])
        #expect(parents(suggestion) == [nil, "c1", "c1", nil, nil])
    }

    @Test func anAnswerWithoutAListGivesOneTopicPerSentence() {
        let suggestion = ChatSuggestion(answer: "Mở beta vào tháng 5 [T1]. Sau đó gửi thông cáo báo chí!", under: parent, parentTitle: "Kế hoạch")

        #expect(titles(suggestion) == ["Mở beta vào tháng 5", "Sau đó gửi thông cáo báo chí"])
        #expect(parents(suggestion) == [nil, nil])
    }

    @Test func aLongListKeepsTheFirstTopicsWithTheirParents() {
        let answer = (1...12).map { "- Item \($0)" }.joined(separator: "\n")
        let suggestion = ChatSuggestion(answer: answer, under: parent, parentTitle: "Plan")

        #expect(suggestion?.topics.count == ChatSuggestion.maximumTopics)
        #expect(titles(suggestion).last == "Item 8")
    }

    @Test func anAnswerWithNoTextSuggestsNothing() {
        #expect(ChatSuggestion(answer: "  [T1] ", under: parent, parentTitle: "Plan") == nil)
    }

    @Test func aSuggestionGoesThroughSuggestionStateAndAcceptsAsOneCommand() throws {
        let fixture = try OutlineFixture("Plan\n  Beta")
        let suggestion = try #require(ChatSuggestion(answer: "- Risks\n  - Legal\n- Press", under: fixture["Plan"], parentTitle: "Plan"))
        var state = SuggestionState(feature: .chat, anchorID: suggestion.parentID)
        state.update(with: ProposalSnapshot(proposal: suggestion.proposal, isComplete: true))

        var engine = fixture.engine
        let accepted = try state.accept(in: engine)
        try engine.execute(accepted.command)

        let risks = try #require(accepted.nodeIDs["c1"])
        #expect(engine.state.childIDs(of: fixture["Plan"]).count == 3)
        #expect(engine.state.node(risks)?.metadata.origin == .ai)
        #expect(engine.state.childIDs(of: risks).compactMap { engine.state.node($0)?.title } == ["Legal"])
    }
}

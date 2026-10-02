import Foundation
import MindMapAICore
import MindMapDomain
import MindMapGraph
import MindMapTestSupport
import Testing

@Suite("Tag suggestions")
struct TagSuggestionsTests {
    private let outline = """
    Trip
      Flights
        Book seats
      Hotels
    """

    private func request(for titles: [String], in fixture: OutlineFixture) throws -> SuggestTagsRequest {
        try #require(SuggestTagsRequest.make(
            for: titles.map { fixture[$0] }, in: fixture.engine.state, language: .english, userLocaleIdentifier: "en_US"
        ))
    }

    @Test func oneTopicSendsItsBranchAndSeveralTopicsSendThemselves() throws {
        var fixture = try OutlineFixture(outline)
        try fixture.engine.execute(TagNodesCommand(nodeIDs: [fixture["Flights"], fixture["Hotels"]], add: [.named("Travel")]))
        try fixture.engine.execute(TagNodesCommand(nodeIDs: [fixture["Hotels"]], add: [.named("Booking")]))

        let branch = try request(for: ["Flights"], in: fixture)
        #expect(branch.topics.map(\.title) == ["Flights", "Book seats"])
        #expect(branch.topics.map(\.reference) == ["t1", "t2"])
        #expect(branch.topics[0].tags == ["Travel"])
        #expect(branch.topics[1].path == ["Trip", "Flights"])
        #expect(branch.availableTags == ["Travel", "Booking"], "most used first")

        let several = try request(for: ["Hotels", "Book seats"], in: fixture)
        #expect(several.topics.map(\.title) == ["Hotels", "Book seats"])
    }

    @Test func aLargeBranchIsCappedAndAGoneTopicMakesNoRequest() throws {
        let titles = (1...20).map { "  Topic \($0)" }.joined(separator: "\n")
        let fixture = try OutlineFixture("Root\n" + titles)

        let capped = try request(for: ["Root"], in: fixture)

        #expect(capped.topics.count == AIProposalLimits.maximumTagSuggestionTopics)
        #expect(SuggestTagsRequest.make(for: [NodeID()], in: fixture.engine.state, language: .english, userLocaleIdentifier: "en_US") == nil)
    }

    @Test func checkingDropsUnknownTopicsRepeatsAndTagsTheTopicHas() throws {
        var fixture = try OutlineFixture(outline)
        try fixture.engine.execute(TagNodesCommand(nodeIDs: [fixture["Flights"]], add: [.named("Travel")]))
        let request = try request(for: ["Flights"], in: fixture)

        let checked = try AITagSuggestions.checked([
            ("t1", ["travel", "#Urgent", "urgent", "  ", "Cost", "Extra"]),
            ("t9", ["Ghost"]),
            ("t2", ["TRAVEL"]),
        ], for: request)

        #expect(checked.entries.map(\.nodeID) == [fixture["Flights"], fixture["Book seats"]])
        #expect(checked.entries[0].names == ["Urgent", "Cost", "Extra"], "at most three, none it has")
        #expect(checked.entries[1].names == ["Travel"], "an existing tag keeps its own spelling")
        #expect(throws: ProposalError.empty) { try AITagSuggestions.checked([("t9", ["Ghost"])], for: request) }
    }

    @Test func acceptingOneIsOneUndoStepWithAITags() throws {
        var fixture = try OutlineFixture(outline)
        let suggestions = AITagSuggestions.tags(
            [fixture["Flights"]: ["Travel", "Urgent"], fixture["Hotels"]: ["Travel"]],
            order: [fixture["Flights"], fixture["Hotels"]]
        )
        var state = TagSuggestionState(suggestions)
        let urgent = try #require(state.suggestions(for: fixture["Flights"]).first { $0.name == "Urgent" })
        let before = fixture.engine.state

        try fixture.engine.execute(try state.accept([urgent.id], in: fixture.engine))
        state.didAccept([urgent.id])

        #expect(fixture.engine.state.tags(of: fixture["Flights"]).map(\.name) == ["Urgent"])
        #expect(fixture.engine.state.nodeTags.values.allSatisfy { $0.origin == .ai })
        #expect(state.suggestions.map(\.name) == ["Travel", "Travel"])
        fixture.engine.undo()
        #expect(fixture.engine.state.tags.isEmpty)
        #expect(fixture.engine.state.nodeTags == before.nodeTags)
        fixture.engine.redo()
        #expect(fixture.engine.state.tags(of: fixture["Flights"]).map(\.name) == ["Urgent"])
    }

    @Test func acceptingAllMakesOneTagPerNameAndEditsAreKept() throws {
        var fixture = try OutlineFixture(outline)
        var state = TagSuggestionState(.tags(
            [fixture["Flights"]: ["Travel"], fixture["Hotels"]: ["travel", "Cost"]],
            order: [fixture["Flights"], fixture["Hotels"]]
        ))
        let cost = try #require(state.suggestions.first { $0.name == "Cost" })
        state.rename(cost.id, to: "  Budget ")
        state.rename(cost.id, to: "#")

        try fixture.engine.execute(try state.accept(nil, in: fixture.engine))

        #expect(fixture.engine.state.mapTags.map(\.name) == ["Travel", "Budget"])
        #expect(fixture.engine.state.tags(of: fixture["Hotels"]).map(\.name) == ["Travel", "Budget"])
        fixture.engine.undo()
        #expect(fixture.engine.state.tags.isEmpty && fixture.engine.state.nodeTags.isEmpty, "all of it is one step")
    }

    @Test func pruneDropsSuggestionsForGoneTopicsAndTagsAlreadyThere() throws {
        var fixture = try OutlineFixture(outline)
        var state = TagSuggestionState(.tags(
            [fixture["Flights"]: ["Travel"], fixture["Hotels"]: ["Cost"]],
            order: [fixture["Flights"], fixture["Hotels"]]
        ))
        try fixture.engine.execute(TagNodesCommand(nodeIDs: [fixture["Flights"]], add: [.named("TRAVEL")]))
        try fixture.engine.execute(DeleteNodeCommand(nodeIDs: [fixture["Hotels"]]))

        state.prune(in: fixture.engine.state)

        #expect(state.isEmpty)
        #expect(throws: ProposalError.unknownTopic("nope")) { try state.accept(["nope"], in: fixture.engine) }
    }

    @Test func theMockAnswersAndRecordsTheRequest() async throws {
        let fixture = try OutlineFixture(outline)
        let provider = MockAIProvider()
        let request = try request(for: ["Hotels"], in: fixture)
        let answer = AITagSuggestions.tags([fixture["Hotels"]: ["Cost"]], order: [fixture["Hotels"]])
        provider.enqueue(.tags(answer), for: .suggestTags)

        #expect(try await provider.suggestTags(request) == answer)
        #expect(provider.requests == [.suggestTags(request)])
        await #expect(throws: AIError.generationFailed) { try await provider.suggestTags(request) }
    }
}

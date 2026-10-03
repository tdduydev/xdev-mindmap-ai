import Foundation
import MindMapAICore
import MindMapDomain
import MindMapGraph
import MindMapTestSupport
import Testing

@Suite("Boundary suggestions")
struct BoundarySuggestionsTests {
    private let outline = """
    Launch
      Ads
      Budget
      Blog
      Hiring
      Video
        Script
    """

    private func groupsRequest(_ fixture: OutlineFixture) throws -> SuggestGroupsRequest {
        try #require(SuggestGroupsRequest.make(
            for: fixture["Launch"], in: fixture.engine.state, language: .english, userLocaleIdentifier: "en_US"
        ))
    }

    private func children(_ fixture: OutlineFixture) -> [String] {
        fixture.engine.state.childIDs(of: fixture["Launch"]).compactMap { fixture.engine.state.node($0)?.title }
    }

    @Test func groupsNeedFourChildrenAndUseReferences() throws {
        let fixture = try OutlineFixture(outline)
        let request = try groupsRequest(fixture)
        #expect(request.children.map(\.reference) == ["t1", "t2", "t3", "t4", "t5"])
        #expect(request.children.map(\.title) == ["Ads", "Budget", "Blog", "Hiring", "Video"])
        #expect(SuggestGroupsRequest.make(for: fixture["Video"], in: fixture.engine.state, language: .english, userLocaleIdentifier: "en_US") == nil)
    }

    @Test func checkingDropsUnknownRepeatsAndGroupsOfOne() throws {
        let fixture = try OutlineFixture(outline)
        let request = try groupsRequest(fixture)

        let checked = try AIGroupSuggestions.checked([
            ("\"Marketing.\"", ["t5", "t1", "t9", "t3", "t1"]),
            ("Money", ["t2"]),
            ("  ", ["t2", "t4"]),
            ("Again", ["t1", "t4"]),
        ], for: request)

        #expect(checked.groups.map(\.title) == ["Marketing"])
        #expect(checked.groups[0].nodeIDs == [fixture["Ads"], fixture["Blog"], fixture["Video"]], "map order")
        #expect(throws: ProposalError.empty) { try AIGroupSuggestions.checked([("One", ["t1"])], for: request) }
    }

    @Test func acceptReordersAddsAIBoundariesAndUndoesInOneStep() throws {
        var fixture = try OutlineFixture(outline)
        let request = try groupsRequest(fixture)
        var state = BoundarySuggestionState(AIGroupSuggestions(parentID: request.parentID, groups: [
            .init(title: "Marketing", nodeIDs: [fixture["Ads"], fixture["Blog"], fixture["Video"]]),
        ]))
        let id = try #require(state.groups.first?.id)
        state.rename(id, to: "Promotion")
        #expect(state.movedCount(in: fixture.engine.state) == 4, "Blog, Video, Budget and Hiring change place")

        let preview = try #require(state.preview(in: fixture.engine))
        #expect(preview.boundaries == [id])
        #expect(children(fixture) == ["Ads", "Budget", "Blog", "Hiring", "Video"], "the preview leaves the map alone")

        try fixture.engine.execute(try state.command(in: fixture.engine))
        #expect(children(fixture) == ["Ads", "Blog", "Video", "Budget", "Hiring"])
        let group = try #require(fixture.engine.state.group(id))
        #expect(group.title == "Promotion")
        #expect(group.origin == .ai)
        #expect(fixture.engine.state.members(of: group) == [fixture["Ads"], fixture["Blog"], fixture["Video"]])
        #expect(preview.state.childIDs(of: fixture["Launch"]) == fixture.engine.state.childIDs(of: fixture["Launch"]))

        _ = fixture.engine.undo()
        #expect(fixture.engine.state.group(id) == nil)
        #expect(children(fixture) == ["Ads", "Budget", "Blog", "Hiring", "Video"])
        _ = fixture.engine.redo()
        #expect(fixture.engine.state.group(id)?.title == "Promotion")
        #expect(children(fixture) == ["Ads", "Blog", "Video", "Budget", "Hiring"])
    }

    @Test func aGroupCrossingAnExistingBoundaryIsLeftOut() throws {
        var fixture = try OutlineFixture(outline)
        try fixture.engine.execute(AddGroupCommand(from: fixture["Budget"], to: fixture["Blog"]))
        let request = try groupsRequest(fixture)
        let crossing = BoundarySuggestionState(AIGroupSuggestions(parentID: request.parentID, groups: [
            .init(title: "Cross", nodeIDs: [fixture["Blog"], fixture["Hiring"]]),
            .init(title: "Last", nodeIDs: [fixture["Hiring"], fixture["Video"]]),
        ]))
        // Blog–Hiring would cross Budget–Blog; Hiring–Video is fine on its own.
        let only = BoundarySuggestionState(AIGroupSuggestions(parentID: request.parentID, groups: [
            .init(title: "Cross", nodeIDs: [fixture["Blog"], fixture["Hiring"]]),
        ]))
        #expect(throws: ProposalError.rejectedByGraph) { try only.command(in: fixture.engine) }
        try fixture.engine.execute(try crossing.command(in: fixture.engine))
        #expect(fixture.engine.state.groups.values.map(\.title).sorted { ($0 ?? "") < ($1 ?? "") } == [nil, "Last"])
    }

    @Test func pruneDropsChildrenThatLeft() throws {
        var fixture = try OutlineFixture(outline)
        var state = BoundarySuggestionState(AIGroupSuggestions(parentID: fixture["Launch"], groups: [
            .init(title: "Two", nodeIDs: [fixture["Ads"], fixture["Blog"]]),
        ]))
        try fixture.engine.execute(DeleteNodeCommand(nodeID: fixture["Blog"]))
        state.prune(in: fixture.engine.state)
        #expect(state.isEmpty)
    }

    @Test func boundaryTitleIsSummarizedRenamedAndAccepted() throws {
        var fixture = try OutlineFixture(outline)
        let id = GroupID()
        try fixture.engine.execute(AddGroupCommand(groupID: id, from: fixture["Hiring"], to: fixture["Video"]))
        let request = try #require(SummarizeBoundaryRequest.make(
            for: id, in: fixture.engine.state, language: .english, userLocaleIdentifier: "en_US"
        ))
        #expect(request.outline.map(\.title) == ["Hiring", "Video", "Script"])
        #expect(request.outline.map(\.depth) == [0, 0, 1])

        let answer = try AIBoundaryTitle.checked("“People and media.”\nmore", for: request)
        #expect(answer.title == "People and media")
        #expect(throws: ProposalError.empty) { try AIBoundaryTitle.checked(" \" ", for: request) }

        var state = BoundarySuggestionState(answer)
        state.rename(id, to: "Team")
        #expect(state.preview(in: fixture.engine)?.boundaries == [id])
        try fixture.engine.execute(try state.command(in: fixture.engine))
        #expect(fixture.engine.state.group(id)?.title == "Team")
        _ = fixture.engine.undo()
        #expect(fixture.engine.state.group(id)?.title == nil)
        _ = fixture.engine.redo()
        #expect(fixture.engine.state.group(id)?.title == "Team")
    }

    @Test func mockProviderAnswersBothRequests() async throws {
        let fixture = try OutlineFixture(outline)
        let provider = MockAIProvider()
        let request = try groupsRequest(fixture)
        let groups = AIGroupSuggestions(parentID: request.parentID, groups: [.init(title: "A", nodeIDs: [fixture["Ads"], fixture["Blog"]])])
        provider.enqueue(.groups(groups), for: .suggestGroups)
        #expect(try await provider.suggestGroups(request) == groups)
        #expect(provider.requests == [.suggestGroups(request)])
    }
}

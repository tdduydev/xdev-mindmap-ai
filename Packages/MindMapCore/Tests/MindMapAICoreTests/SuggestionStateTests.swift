import Foundation
import MindMapAICore
import MindMapDomain
import MindMapGraph
import MindMapTestSupport
import Testing

struct SuggestionStateTests {
    private let outline = """
    Trip
      Flights
      Hotels
    """

    private func complete(_ proposal: AIProposal) -> ProposalSnapshot {
        ProposalSnapshot(proposal: proposal, isComplete: true)
    }

    // MARK: Streaming

    @Test func followsTheStreamAndKeepsPreviewIDsStable() throws {
        let fixture = try OutlineFixture(outline)
        var state = SuggestionState(feature: .expandTopic, anchorID: fixture["Trip"])

        state.update(with: ProposalSnapshot(proposal: .suggestions(["Fo"], under: fixture["Trip"]), isComplete: false))
        let firstID = try #require(state.topics.first?.previewID)
        #expect(!state.isComplete)

        state.update(with: complete(.suggestions(["Food", "Weather"], under: fixture["Trip"])))
        #expect(state.topics.map(\.title) == ["Food", "Weather"])
        #expect(state.topics.first?.previewID == firstID, "the canvas keeps the topic's place while it streams")
        #expect(state.isComplete)
    }

    @Test func partialTreesWaitForTheirParents() throws {
        let fixture = try OutlineFixture("New map")
        var state = SuggestionState(feature: .generateMap, anchorID: fixture["New map"])
        let proposal = AIProposal(feature: .generateMap, anchor: .root, topics: [
            ProposedTopic(temporaryID: "t2", parentTemporaryID: "t1", title: "Tomatoes"),
            ProposedTopic(temporaryID: "t3", parentTemporaryID: "", title: "Flowers"),
            ProposedTopic(temporaryID: "t4", parentTemporaryID: "t4", title: "Loop"),
        ])

        state.update(with: ProposalSnapshot(proposal: proposal, isComplete: false))
        #expect(state.topics.map(\.title) == ["Flowers"])

        var later = proposal
        later.topics.append(ProposedTopic(temporaryID: "t1", title: "Vegetables"))
        state.update(with: complete(later))
        #expect(state.topics.map(\.title) == ["Flowers", "Vegetables", "Tomatoes"])
    }

    // MARK: Editing

    @Test func editsSurviveLaterSnapshots() throws {
        let fixture = try OutlineFixture(outline)
        var state = SuggestionState(feature: .brainstorm, anchorID: fixture["Trip"])
        let proposal = AIProposal.suggestions(["Food", "Weather", "Visa"], under: fixture["Trip"])
        state.update(with: ProposalSnapshot(proposal: proposal, isComplete: false))

        state.rename("s1", to: "  Street food ")
        state.rename("s2", to: "   ")
        state.remove("s3")
        state.update(with: complete(proposal))

        #expect(state.topics.map(\.title) == ["Street food", "Weather"])
    }

    @Test func removingATopicRemovesItsSuggestedSubtopics() throws {
        let fixture = try OutlineFixture("Garden")
        var state = SuggestionState(feature: .generateMap, anchorID: fixture["Garden"])
        state.update(with: complete(AIProposal(feature: .generateMap, anchor: .root, topics: [
            ProposedTopic(temporaryID: "t1", title: "Vegetables"),
            ProposedTopic(temporaryID: "t2", parentTemporaryID: "t1", title: "Tomatoes"),
            ProposedTopic(temporaryID: "t3", title: "Flowers"),
        ])))

        state.remove("t1")

        #expect(state.topics.map(\.title) == ["Flowers"])
    }

    // MARK: Preview

    @Test func previewDrawsSuggestionsWithoutTouchingTheMap() throws {
        let fixture = try OutlineFixture(outline)
        var state = SuggestionState(feature: .expandTopic, anchorID: fixture["Flights"])
        state.update(with: complete(.suggestions(["Window seat"], under: fixture["Flights"])))

        let preview = state.preview(in: fixture.engine)
        let drawable = state.drawableTopics(in: preview)

        #expect(fixture.childTitles(of: "Flights").isEmpty)
        #expect(preview.children(of: fixture["Flights"]).map(\.title) == ["Window seat"])
        #expect(drawable.values.sorted() == ["s1"])
    }

    @Test func previewLeavesOutSuggestionsWhoseAnchorIsGone() throws {
        var fixture = try OutlineFixture(outline)
        var state = SuggestionState(feature: .expandTopic, anchorID: fixture["Hotels"])
        state.update(with: complete(.suggestions(["Pool"], under: fixture["Hotels"])))

        try fixture.engine.execute(DeleteNodeCommand(nodeID: fixture["Hotels"]))
        let preview = state.preview(in: fixture.engine)

        #expect(preview == fixture.state)
        #expect(state.drawableTopics(in: preview).isEmpty)
        #expect(throws: ProposalError.anchorNotFound) { try state.accept(in: fixture.engine) }
    }

    // MARK: Accepting

    @Test func acceptAllIsOneUndoStepMarkedAsAI() throws {
        var fixture = try OutlineFixture(outline)
        let before = fixture.state
        var state = SuggestionState(feature: .expandTopic, anchorID: fixture["Trip"])
        state.update(with: complete(.suggestions(["Food", "Weather"], under: fixture["Trip"])))

        let accepted = try state.accept(in: fixture.engine)
        try fixture.engine.execute(accepted.command)
        state.didAccept(accepted.nodeIDs)

        #expect(fixture.childTitles(of: "Trip") == ["Flights", "Hotels", "Food", "Weather"])
        #expect(fixture.state.children(of: fixture["Trip"]).suffix(2).allSatisfy { $0.metadata.origin == .ai })
        #expect(state.isEmpty)

        fixture.engine.undo()
        #expect(fixture.state.nodes == before.nodes)
        fixture.engine.redo()
        #expect(fixture.childTitles(of: "Trip") == ["Flights", "Hotels", "Food", "Weather"])
    }

    @Test func acceptingOneKeepsTheOthers() throws {
        var fixture = try OutlineFixture(outline)
        var state = SuggestionState(feature: .brainstorm, anchorID: fixture["Trip"])
        state.update(with: complete(.suggestions(["Food", "Weather"], under: fixture["Trip"])))

        let accepted = try state.accept(["s2"], in: fixture.engine)
        try fixture.engine.execute(accepted.command)
        state.didAccept(accepted.nodeIDs)

        #expect(fixture.childTitles(of: "Trip") == ["Flights", "Hotels", "Weather"])
        #expect(state.topics.map(\.title) == ["Food"])
    }

    @Test func nestedSuggestionsMoveUnderTheAcceptedParent() throws {
        var fixture = try OutlineFixture("Garden")
        var state = SuggestionState(feature: .generateMap, anchorID: fixture["Garden"])
        state.update(with: complete(AIProposal(feature: .generateMap, anchor: .root, topics: [
            ProposedTopic(temporaryID: "t1", title: "Vegetables"),
            ProposedTopic(temporaryID: "t2", parentTemporaryID: "t1", title: "Tomatoes"),
            ProposedTopic(temporaryID: "t3", parentTemporaryID: "t2", title: "Cherry"),
        ])))

        let first = try state.accept(["t1"], in: fixture.engine)
        try fixture.engine.execute(first.command)
        state.didAccept(first.nodeIDs)
        let vegetablesID = try #require(first.nodeIDs["t1"])
        #expect(state.topics.map(\.anchorID) == [vegetablesID, vegetablesID])

        let second = try state.accept(in: fixture.engine)
        try fixture.engine.execute(second.command)
        let tomatoesID = try #require(second.nodeIDs["t2"])
        #expect(fixture.state.children(of: vegetablesID).map(\.title) == ["Tomatoes"])
        #expect(fixture.state.children(of: tomatoesID).map(\.title) == ["Cherry"])
    }

    @Test func nothingIsAcceptedWhileStreaming() throws {
        let fixture = try OutlineFixture(outline)
        var state = SuggestionState(feature: .expandTopic, anchorID: fixture["Trip"])
        state.update(with: ProposalSnapshot(proposal: .suggestions(["Food"], under: fixture["Trip"]), isComplete: false))

        #expect(throws: ProposalError.empty) { try state.accept(in: fixture.engine) }
    }
}

struct SuggestionStreamTests {
    @Test func defaultStreamYieldsOneCompleteSnapshot() async throws {
        let fixture = try OutlineFixture("Trip")
        let provider = OneShotProvider(proposal: .suggestions(["Food"], under: fixture["Trip"]))
        let context = try AIContextBuilder().context(for: fixture["Trip"], in: fixture.state, language: .english, userLocaleIdentifier: "en_US")

        var snapshots: [ProposalSnapshot] = []
        for try await snapshot in provider.streamSuggestions(.expandTopic(ExpandTopicRequest(context: context))) {
            snapshots.append(snapshot)
        }

        #expect(snapshots.map(\.isComplete) == [true])
        #expect(snapshots.first?.proposal.topics.map(\.title) == ["Food"])
    }

    @Test func mockStreamsPartialsThenTheFinalAnswer() async throws {
        let fixture = try OutlineFixture("Trip")
        let provider = MockAIProvider()
        provider.enqueue(.stream([
            .suggestions(["Fo"], under: fixture["Trip"], feature: .brainstorm),
            .suggestions(["Food", "Visa"], under: fixture["Trip"], feature: .brainstorm),
        ]), for: .brainstorm)
        let context = try AIContextBuilder().context(for: fixture["Trip"], in: fixture.state, language: .english, userLocaleIdentifier: "en_US")

        var snapshots: [ProposalSnapshot] = []
        for try await snapshot in provider.streamSuggestions(.brainstorm(BrainstormRequest(context: context))) {
            snapshots.append(snapshot)
        }

        #expect(snapshots.map(\.isComplete) == [false, true])
        #expect(provider.requests.count == 1)
    }

    @Test func cancellingEndsAHangingRequest() async throws {
        let fixture = try OutlineFixture("Trip")
        let provider = MockAIProvider()
        provider.enqueue(.hang, for: .expandTopic)
        let context = try AIContextBuilder().context(for: fixture["Trip"], in: fixture.state, language: .english, userLocaleIdentifier: "en_US")

        let task = Task {
            for try await _ in provider.streamSuggestions(.expandTopic(ExpandTopicRequest(context: context))) {}
        }
        task.cancel()

        // A cancelled stream ends instead of throwing; reaching this line in
        // less than the hour the mock would wait is the check.
        _ = try? await task.value
        #expect(task.isCancelled)
    }
}

/// A provider with no streaming of its own, to check the protocol's default.
private struct OneShotProvider: AIProvider {
    let proposal: AIProposal

    func capabilities() async -> AICapabilities { .readyForTesting }
    func generateMap(_ request: GenerateMapRequest) async throws -> AIProposal { proposal }
    func expandTopic(_ request: ExpandTopicRequest) async throws -> AIProposal { proposal }
    func brainstorm(_ request: BrainstormRequest) async throws -> AIProposal { proposal }
    func rewrite(_ request: RewriteRequest) async throws -> AIRewrite { throw AIError.generationFailed }
    func summarize(_ request: SummarizeRequest) async throws -> AISummary { throw AIError.generationFailed }
    func findMissingTopics(_ request: MissingTopicsRequest) async throws -> AIProposal { proposal }
}

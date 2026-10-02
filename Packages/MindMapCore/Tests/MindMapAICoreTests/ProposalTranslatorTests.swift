import Foundation
import MindMapAICore
import MindMapDomain
import MindMapGraph
import MindMapTestSupport
import Testing

struct ProposalTranslatorTests {
    private let outline = """
    Trip
      Flights
      Hotels
    """

    // MARK: Accepting topics

    @Test func addsSuggestionsUnderTheAnchorAsOneUndoStep() throws {
        var fixture = try OutlineFixture(outline)
        let before = fixture.state
        let proposal = AIProposal.suggestions(["Food", "Weather"], under: fixture["Trip"])

        let accepted = try ProposalTranslator.accept(proposal, in: fixture.engine)
        #expect(fixture.state == before, "accepting builds a command; it does not run it")
        try fixture.engine.execute(accepted.command)

        #expect(fixture.childTitles(of: "Trip") == ["Flights", "Hotels", "Food", "Weather"])
        let addedID = try #require(accepted.nodeIDs["s1"])
        #expect(fixture.state.node(addedID)?.metadata.origin == .ai)

        fixture.engine.undo()
        #expect(fixture.state.nodes == before.nodes)
        #expect(fixture.childTitles(of: "Trip") == ["Flights", "Hotels"])

        fixture.engine.redo()
        #expect(fixture.childTitles(of: "Trip") == ["Flights", "Hotels", "Food", "Weather"])
    }

    @Test func buildsAGeneratedTreeUnderTheRootParentsFirst() throws {
        var fixture = try OutlineFixture("New map")
        // The model listed a subtopic before its parent.
        let proposal = AIProposal(feature: .generateMap, anchor: .root, suggestedMapTitle: "Garden", topics: [
            ProposedTopic(temporaryID: "t2", parentTemporaryID: "t1", title: "Tomatoes"),
            ProposedTopic(temporaryID: "t1", parentTemporaryID: "", title: "Vegetables"),
            ProposedTopic(temporaryID: "t3", parentTemporaryID: nil, title: "Flowers"),
        ])

        let ordered = try ProposalTranslator.validate(proposal)
        #expect(ordered.map(\.temporaryID) == ["t1", "t2", "t3"])

        let accepted = try ProposalTranslator.accept(proposal, in: fixture.engine)
        try fixture.engine.execute(accepted.command)

        #expect(fixture.childTitles(of: "New map") == ["Vegetables", "Flowers"])
        let vegetablesID = try #require(accepted.nodeIDs["t1"])
        #expect(fixture.state.children(of: vegetablesID).map(\.title) == ["Tomatoes"])

        fixture.engine.undo()
        #expect(fixture.childTitles(of: "New map").isEmpty)
        fixture.engine.redo()
        #expect(fixture.childTitles(of: "New map") == ["Vegetables", "Flowers"])
    }

    @Test func acceptingANestedTopicBringsItsProposedParents() throws {
        var fixture = try OutlineFixture(outline)
        let proposal = AIProposal(feature: .expandTopic, anchor: .node(fixture["Flights"]), topics: [
            ProposedTopic(temporaryID: "a", title: "Airlines"),
            ProposedTopic(temporaryID: "b", parentTemporaryID: "a", title: "Budget"),
            ProposedTopic(temporaryID: "c", title: "Airports"),
        ])

        let accepted = try ProposalTranslator.accept(proposal, topics: ["b"], in: fixture.engine)
        try fixture.engine.execute(accepted.command)

        #expect(Set(accepted.nodeIDs.keys) == ["a", "b"])
        #expect(fixture.childTitles(of: "Flights") == ["Airlines"])
    }

    @Test func trimsTitlesAndDropsEmptyNotes() throws {
        var fixture = try OutlineFixture(outline)
        let proposal = AIProposal(feature: .brainstorm, anchor: .node(fixture["Hotels"]), topics: [
            ProposedTopic(temporaryID: " s1 ", title: "  Near the beach \n", note: "   "),
        ])

        let accepted = try ProposalTranslator.accept(proposal, in: fixture.engine)
        try fixture.engine.execute(accepted.command)

        let node = try #require(fixture.state.children(of: fixture["Hotels"]).first)
        #expect(node.title == "Near the beach")
        #expect(node.note == nil)
        #expect(accepted.nodeIDs["s1"] == node.id)
    }

    // MARK: Refusing proposals

    @Test func refusesMalformedProposals() throws {
        let fixture = try OutlineFixture(outline)
        let anchor = ProposalAnchor.node(fixture["Trip"])
        func proposal(_ topics: [ProposedTopic]) -> AIProposal {
            AIProposal(feature: .expandTopic, anchor: anchor, topics: topics)
        }

        #expect(throws: ProposalError.empty) {
            try ProposalTranslator.validate(proposal([]))
        }
        #expect(throws: ProposalError.emptyTemporaryID) {
            try ProposalTranslator.validate(proposal([ProposedTopic(temporaryID: " ", title: "A")]))
        }
        #expect(throws: ProposalError.duplicateTemporaryID("t1")) {
            try ProposalTranslator.validate(proposal([
                ProposedTopic(temporaryID: "t1", title: "A"),
                ProposedTopic(temporaryID: "t1", title: "B"),
            ]))
        }
        #expect(throws: ProposalError.emptyTitle(temporaryID: "t1")) {
            try ProposalTranslator.validate(proposal([ProposedTopic(temporaryID: "t1", title: "  ")]))
        }
        #expect(throws: ProposalError.unknownParent(temporaryID: "t1", parent: "t9")) {
            try ProposalTranslator.validate(proposal([ProposedTopic(temporaryID: "t1", parentTemporaryID: "t9", title: "A")]))
        }
        #expect(throws: ProposalError.cycle(temporaryID: "t1")) {
            try ProposalTranslator.validate(proposal([
                ProposedTopic(temporaryID: "t0", title: "Fine"),
                ProposedTopic(temporaryID: "t1", parentTemporaryID: "t2", title: "A"),
                ProposedTopic(temporaryID: "t2", parentTemporaryID: "t1", title: "B"),
            ]))
        }
        #expect(throws: ProposalError.cycle(temporaryID: "t1")) {
            try ProposalTranslator.validate(proposal([ProposedTopic(temporaryID: "t1", parentTemporaryID: "t1", title: "A")]))
        }
        #expect(throws: ProposalError.unknownTopic("zz")) {
            try ProposalTranslator.accept(
                proposal([ProposedTopic(temporaryID: "t1", title: "A")]),
                topics: ["zz"],
                in: fixture.engine
            )
        }
    }

    @Test func refusesAProposalWhoseAnchorWasDeleted() throws {
        var fixture = try OutlineFixture(outline)
        let proposal = AIProposal.suggestions(["Seats"], under: fixture["Flights"])
        try fixture.engine.execute(DeleteNodeCommand(nodeID: fixture["Flights"]))
        let before = fixture.state

        #expect(throws: ProposalError.anchorNotFound) {
            try ProposalTranslator.accept(proposal, in: fixture.engine)
        }
        #expect(fixture.state == before)
    }

    @Test func refusesARootAnchorOnAMapWithoutARoot() throws {
        let engine = try GraphEngine(state: GraphState(map: MindMap(title: "Empty")))
        let proposal = AIProposal(feature: .generateMap, anchor: .root, topics: [ProposedTopic(temporaryID: "t1", title: "A")])

        #expect(throws: ProposalError.anchorNotFound) {
            try ProposalTranslator.accept(proposal, in: engine)
        }
    }

    // MARK: Rewrite and summary

    @Test func acceptingARewriteRenamesTheTopic() throws {
        var fixture = try OutlineFixture(outline)
        let rewrite = AIRewrite(nodeID: fixture["Hotels"], originalTitle: "Hotels", suggestions: ["Places to stay"])

        let command = try ProposalTranslator.accept(title: " Places to stay ", from: rewrite, in: fixture.engine)
        try fixture.engine.execute(command)
        #expect(fixture.state.node(fixture["Hotels"])?.title == "Places to stay")

        fixture.engine.undo()
        #expect(fixture.state.node(fixture["Hotels"])?.title == "Hotels")
        fixture.engine.redo()
        #expect(fixture.state.node(fixture["Hotels"])?.title == "Places to stay")
    }

    @Test func acceptingASummaryAppendsItToTheNote() throws {
        var fixture = try OutlineFixture(outline)
        try fixture.engine.execute(UpdateNodeCommand(nodeID: fixture["Trip"], .note("My own words")))
        let summary = AISummary(nodeID: fixture["Trip"], text: "Flights and hotels are planned.")

        let command = try ProposalTranslator.accept(summary, in: fixture.engine)
        try fixture.engine.execute(command)
        #expect(fixture.state.node(fixture["Trip"])?.note == "My own words\n\nFlights and hotels are planned.")

        fixture.engine.undo()
        #expect(fixture.state.node(fixture["Trip"])?.note == "My own words")
        fixture.engine.redo()
        #expect(fixture.state.node(fixture["Trip"])?.note == "My own words\n\nFlights and hotels are planned.")
    }

    @Test func refusesAnEmptySummaryOrTitle() throws {
        let fixture = try OutlineFixture(outline)
        #expect(throws: ProposalError.empty) {
            try ProposalTranslator.accept(AISummary(nodeID: fixture["Trip"], text: " "), in: fixture.engine)
        }
        let rewrite = AIRewrite(nodeID: fixture["Trip"], originalTitle: "Trip", suggestions: [])
        #expect(throws: ProposalError.emptyTitle(temporaryID: "")) {
            try ProposalTranslator.accept(title: "", from: rewrite, in: fixture.engine)
        }
    }
}

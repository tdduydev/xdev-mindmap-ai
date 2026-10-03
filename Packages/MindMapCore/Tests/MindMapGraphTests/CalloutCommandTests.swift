import Foundation
import MindMapDomain
@testable import MindMapGraph
import Testing

@Suite("Callout")
struct CalloutCommandTests {
    static let outline = """
    Root
      A
        A1
      B
      C
    """

    @Test func addEditAndRemoveAreEachOneUndoStep() throws {
        var fixture = try GraphFixture(Self.outline)
        let a = fixture["A"]

        try expectUndoAndRedo(SetCalloutCommand(nodeIDs: [a], text: "Check the budget"), on: &fixture)
        #expect(fixture.state.node(a)?.callout == "Check the budget")

        try expectUndoAndRedo(SetCalloutCommand(nodeIDs: [a], text: "Due Friday"), on: &fixture)
        #expect(fixture.state.node(a)?.callout == "Due Friday")

        try expectUndoAndRedo(SetCalloutCommand(nodeIDs: [a], text: nil), on: &fixture)
        #expect(fixture.state.node(a)?.callout == nil)
    }

    @Test func textIsTrimmedCappedAndBlankRemovesIt() throws {
        var fixture = try GraphFixture(Self.outline)
        let a = fixture["A"]
        try fixture.engine.execute(SetCalloutCommand(nodeIDs: [a], text: "  Note \n"))
        #expect(fixture.state.node(a)?.callout == "Note")

        try fixture.engine.execute(SetCalloutCommand(nodeIDs: [a], text: String(repeating: "x", count: 400)))
        #expect(fixture.state.node(a)?.callout?.count == MindNode.maximumCalloutLength)

        try expectUndoAndRedo(SetCalloutCommand(nodeIDs: [a], text: " \n "), on: &fixture)
        #expect(fixture.state.node(a)?.callout == nil)
    }

    @Test func setsEveryGivenTopic() throws {
        var fixture = try GraphFixture(Self.outline)
        try expectUndoAndRedo(SetCalloutCommand(nodeIDs: [fixture["A"], fixture["B"]], text: "Later"), on: &fixture)
        #expect(fixture.state.node(fixture["A"])?.callout == "Later")
        #expect(fixture.state.node(fixture["B"])?.callout == "Later")
        #expect(fixture.state.node(fixture["C"])?.callout == nil)
    }

    @Test func sameTextChangesNothing() throws {
        var fixture = try GraphFixture(Self.outline)
        try fixture.engine.execute(SetCalloutCommand(nodeIDs: [fixture["A"]], text: "Later"))
        let changes = try fixture.engine.execute(SetCalloutCommand(nodeIDs: [fixture["A"]], text: " Later "))
        #expect(changes.isEmpty)
    }

    @Test func missingTopicIsRefusedAndChangesNothing() throws {
        var fixture = try GraphFixture(Self.outline)
        let before = fixture.state
        let ghost = NodeID()
        #expect(throws: GraphError.nodeNotFound(ghost)) {
            try fixture.engine.execute(SetCalloutCommand(nodeIDs: [fixture["A"], ghost], text: "Later"))
        }
        #expect(fixture.state == before)
    }

    /// The callout is a field of the node, so it goes in the delete's own
    /// transaction and comes back with the topic on undo.
    @Test func deletingTheTopicTakesItsCalloutAndUndoBringsItBack() throws {
        var fixture = try GraphFixture(Self.outline)
        try fixture.engine.execute(SetCalloutCommand(nodeIDs: [fixture["A1"]], text: "Inside"))
        try fixture.engine.execute(SetCalloutCommand(nodeIDs: [fixture["A"]], text: "Branch"))

        try expectUndoAndRedo(DeleteNodeCommand(nodeID: fixture["A"]), on: &fixture)
        #expect(!fixture.state.nodes.values.contains { $0.callout != nil })
        fixture.engine.undo()
        #expect(fixture.state.node(fixture["A"])?.callout == "Branch")
        #expect(fixture.state.node(fixture["A1"])?.callout == "Inside")
    }

    @Test func mergeKeepsTheSurvivorsCalloutElseTakesAMergedOne() throws {
        var fixture = try GraphFixture(Self.outline)
        try fixture.engine.execute(SetCalloutCommand(nodeIDs: [fixture["B"]], text: "From B"))
        try fixture.engine.execute(SetCalloutCommand(nodeIDs: [fixture["C"]], text: "From C"))
        try expectUndoAndRedo(MergeNodesCommand(into: fixture["A"], merging: [fixture["B"], fixture["C"]]), on: &fixture)
        #expect(fixture.state.node(fixture["A"])?.callout == "From B")

        var other = try GraphFixture(Self.outline)
        try other.engine.execute(SetCalloutCommand(nodeIDs: [other["A"]], text: "Own"))
        try other.engine.execute(SetCalloutCommand(nodeIDs: [other["B"]], text: "From B"))
        try other.engine.execute(MergeNodesCommand(into: other["A"], merging: [other["B"]]))
        #expect(other.state.node(other["A"])?.callout == "Own")
    }
}

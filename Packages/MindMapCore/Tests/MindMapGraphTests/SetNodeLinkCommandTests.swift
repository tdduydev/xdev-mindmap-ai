import Foundation
import MindMapDomain
@testable import MindMapGraph
import Testing

@Suite("Topic link")
struct SetNodeLinkCommandTests {
    static let outline = """
    Root
      A
      B
      C
    """

    static let example = TopicLink(string: "https://example.com")
    static let other = TopicLink(string: "mailto:team@example.com")

    @Test func addEditAndRemoveAreEachOneUndoStep() throws {
        var fixture = try GraphFixture(Self.outline)
        let a = fixture["A"]

        try expectUndoAndRedo(SetNodeLinkCommand(nodeIDs: [a], link: Self.example), on: &fixture)
        #expect(fixture.state.node(a)?.link == Self.example)

        try expectUndoAndRedo(SetNodeLinkCommand(nodeIDs: [a], link: Self.other), on: &fixture)
        #expect(fixture.state.node(a)?.link == Self.other)

        try expectUndoAndRedo(SetNodeLinkCommand(nodeIDs: [a], link: nil), on: &fixture)
        #expect(fixture.state.node(a)?.link == nil)
    }

    @Test func setsEveryGivenTopic() throws {
        var fixture = try GraphFixture(Self.outline)
        try expectUndoAndRedo(SetNodeLinkCommand(nodeIDs: [fixture["A"], fixture["B"]], link: Self.example), on: &fixture)
        #expect(fixture.state.node(fixture["A"])?.link == Self.example)
        #expect(fixture.state.node(fixture["B"])?.link == Self.example)
        #expect(fixture.state.node(fixture["C"])?.link == nil)
    }

    @Test func sameValueChangesNothing() throws {
        var fixture = try GraphFixture(Self.outline)
        try fixture.engine.execute(SetNodeLinkCommand(nodeIDs: [fixture["A"]], link: Self.example))
        let changes = try fixture.engine.execute(SetNodeLinkCommand(nodeIDs: [fixture["A"]], link: Self.example))
        #expect(changes.isEmpty)
    }

    @Test func missingTopicIsRefusedAndChangesNothing() throws {
        var fixture = try GraphFixture(Self.outline)
        let before = fixture.state
        let ghost = NodeID()
        #expect(throws: GraphError.nodeNotFound(ghost)) {
            try fixture.engine.execute(SetNodeLinkCommand(nodeIDs: [fixture["A"], ghost], link: Self.example))
        }
        #expect(fixture.state == before)
    }

    @Test func mergeKeepsTheSurvivorsLinkElseTakesAMergedOne() throws {
        var fixture = try GraphFixture(Self.outline)
        try fixture.engine.execute(SetNodeLinkCommand(nodeIDs: [fixture["B"]], link: Self.example))
        try fixture.engine.execute(SetNodeLinkCommand(nodeIDs: [fixture["C"]], link: Self.other))

        try expectUndoAndRedo(MergeNodesCommand(into: fixture["A"], merging: [fixture["B"], fixture["C"]]), on: &fixture)
        #expect(fixture.state.node(fixture["A"])?.link == Self.example)
    }

    @Test func mergeLeavesTheSurvivorsOwnLink() throws {
        var fixture = try GraphFixture(Self.outline)
        try fixture.engine.execute(SetNodeLinkCommand(nodeIDs: [fixture["A"]], link: Self.other))
        try fixture.engine.execute(SetNodeLinkCommand(nodeIDs: [fixture["B"]], link: Self.example))

        try fixture.engine.execute(MergeNodesCommand(into: fixture["A"], merging: [fixture["B"]]))
        #expect(fixture.state.node(fixture["A"])?.link == Self.other)
    }

    @Test func splitKeepsTheLinkOnTheFirstTopic() throws {
        var fixture = try GraphFixture(Self.outline)
        let a = fixture["A"]
        try fixture.engine.execute(UpdateNodeCommand(nodeID: a, .title("One\nTwo")))
        try fixture.engine.execute(SetNodeLinkCommand(nodeIDs: [a], link: Self.example))

        try fixture.engine.execute(SplitNodeCommand(nodeID: a))
        let linked = fixture.state.nodes.values.filter { $0.link != nil }
        #expect(linked.map(\.id) == [a])
    }
}

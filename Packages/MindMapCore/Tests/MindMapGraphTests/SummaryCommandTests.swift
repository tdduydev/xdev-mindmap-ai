import Foundation
import MindMapDomain
@testable import MindMapGraph
import Testing

@Suite("Summaries")
struct SummaryCommandTests {
    static let outline = """
    Root
      A
        A1
      B
      C
      D
      E
    """

    static func members(_ id: GroupID, in fixture: GraphFixture) -> [String]? {
        guard let group = fixture.state.group(id) else { return nil }
        return fixture.state.members(of: group)?.compactMap { fixture.state.node($0)?.title }
    }

    static func summary(
        from first: String,
        to last: String,
        in fixture: inout GraphFixture
    ) throws -> (group: GroupID, topic: NodeID) {
        let group = GroupID()
        let topic = NodeID()
        try fixture.engine.execute(AddSummaryCommand(groupID: group, nodeID: topic, from: fixture[first], to: fixture[last], title: "Sum"))
        return (group, topic)
    }

    // MARK: Commands

    @Test func addBracketsARunAndAddsTheSummaryTopic() throws {
        var fixture = try GraphFixture(Self.outline)
        let groupID = GroupID()
        let topicID = NodeID()

        try expectUndoAndRedo(
            AddSummaryCommand(groupID: groupID, nodeID: topicID, from: fixture["D"], to: fixture["B"], title: "Middle"),
            on: &fixture
        )

        let group = try #require(fixture.state.group(groupID))
        #expect(group.kind == .summary)
        #expect(group.summaryNodeID == topicID)
        #expect(Self.members(groupID, in: fixture) == ["B", "C", "D"])
        let topic = try #require(fixture.state.node(topicID))
        #expect(topic.parentID == fixture["Root"])
        #expect(topic.title == "Middle")
        // In the tree as the last child, out of every run.
        #expect(fixture.state.childIDs(of: fixture["Root"]).last == topicID)
        #expect(!fixture.state.runSiblingIDs(of: fixture["Root"]).contains(topicID))
        #expect(GraphValidator.validate(fixture.state).isEmpty)
    }

    @Test func refusesTheRootFloatingTopicsAndEndsUnderDifferentParents() throws {
        var fixture = try GraphFixture(Self.outline)
        let floatingID = NodeID()
        try fixture.engine.execute(AddFloatingTopicCommand(nodeID: floatingID, title: "Loose", position: TopicPosition(x: 400, y: 400)))

        #expect(throws: GraphError.cannotGroupRoot) {
            try fixture.engine.execute(AddSummaryCommand(from: fixture["Root"]))
        }
        #expect(throws: GraphError.cannotGroupRoot) {
            try fixture.engine.execute(AddSummaryCommand(from: floatingID))
        }
        #expect(throws: GraphError.notSiblings(fixture["B"])) {
            try fixture.engine.execute(AddSummaryCommand(from: fixture["A1"], to: fixture["B"]))
        }
        #expect(fixture.state.groups.isEmpty)
        #expect(fixture.state.childIDs(of: fixture["Root"]).count == 5)
    }

    @Test func refusesTheSameRunTwiceAndCrossingSummaries() throws {
        var fixture = try GraphFixture(Self.outline)
        let existing = try Self.summary(from: "A", to: "C", in: &fixture)

        #expect(throws: GraphError.groupAlreadyCoversRun(existing.group)) {
            try fixture.engine.execute(AddSummaryCommand(from: fixture["C"], to: fixture["A"]))
        }
        #expect(throws: GraphError.groupsWouldCross(existing.group)) {
            try fixture.engine.execute(AddSummaryCommand(from: fixture["B"], to: fixture["D"]))
        }
        // The summary topic is not a sibling a run can reach.
        #expect(throws: GraphError.notSiblings(existing.topic)) {
            try fixture.engine.execute(AddSummaryCommand(from: fixture["E"], to: existing.topic))
        }
        // Nesting is fine, and a boundary may share or cross a summary's run.
        try fixture.engine.execute(AddSummaryCommand(from: fixture["A"], to: fixture["B"]))
        try fixture.engine.execute(AddGroupCommand(from: fixture["A"], to: fixture["C"]))
        try fixture.engine.execute(AddGroupCommand(from: fixture["D"], to: fixture["E"]))
        try fixture.engine.execute(AddSummaryCommand(from: fixture["D"], to: fixture["E"]))
        var crossing = try GraphFixture(Self.outline)
        _ = try Self.summary(from: "A", to: "C", in: &crossing)
        try crossing.engine.execute(AddGroupCommand(from: crossing["B"], to: crossing["D"]))
        #expect(GraphValidator.validate(crossing.state).isEmpty)
        #expect(GraphValidator.validate(fixture.state).isEmpty)
    }

    @Test func theSummaryTopicIsAnOrdinaryTopic() throws {
        var fixture = try GraphFixture(Self.outline)
        let summary = try Self.summary(from: "B", to: "C", in: &fixture)

        try expectUndoAndRedo(UpdateNodeCommand(nodeID: summary.topic, .title("Renamed")), on: &fixture)
        try expectUndoAndRedo(AddNodeCommand(.child(of: summary.topic), title: "Detail"), on: &fixture)

        #expect(fixture.state.node(summary.topic)?.title == "Renamed")
        #expect(fixture.state.children(of: summary.topic).map(\.title) == ["Detail"])
        #expect(fixture.state.group(summary.group) != nil)
    }

    @Test func removeTakesTheBracketAndTheSummaryBranch() throws {
        var fixture = try GraphFixture(Self.outline)
        let summary = try Self.summary(from: "B", to: "C", in: &fixture)
        try fixture.engine.execute(AddNodeCommand(.child(of: summary.topic), title: "Detail"))

        let changes = try expectUndoAndRedo(RemoveSummaryCommand(groupID: summary.group), on: &fixture)

        #expect(changes.deletedGroupIDs == [summary.group])
        #expect(fixture.state.node(summary.topic) == nil)
        #expect(fixture.childTitles(of: "Root") == ["A", "B", "C", "D", "E"])
    }

    @Test func removeRefusesABoundaryAndAMissingGroup() throws {
        var fixture = try GraphFixture(Self.outline)
        let boundary = GroupID()
        try fixture.engine.execute(AddGroupCommand(groupID: boundary, from: fixture["B"]))

        #expect(throws: GraphError.groupNotFound(boundary)) {
            try fixture.engine.execute(RemoveSummaryCommand(groupID: boundary))
        }
        let missing = GroupID()
        #expect(throws: GraphError.groupNotFound(missing)) {
            try fixture.engine.execute(RemoveSummaryCommand(groupID: missing))
        }
    }

    @Test func deletingTheSummaryTopicRemovesTheBracket() throws {
        var fixture = try GraphFixture(Self.outline)
        let summary = try Self.summary(from: "B", to: "C", in: &fixture)

        try expectUndoAndRedo(DeleteNodeCommand(nodeID: summary.topic), on: &fixture)

        #expect(fixture.state.group(summary.group) == nil)
    }

    // MARK: Kept valid while topics move (the boundary rules, FR-ORG-14)

    @Test func aTopicAddedInsideTheRunJoinsIt() throws {
        var fixture = try GraphFixture(Self.outline)
        let summary = try Self.summary(from: "B", to: "D", in: &fixture)

        try fixture.engine.execute(AddNodeCommand(.sibling(after: fixture["B"]), title: "New"))

        #expect(Self.members(summary.group, in: fixture) == ["B", "New", "C", "D"])
    }

    @Test func deletingAnEndMovesItInward() throws {
        var fixture = try GraphFixture(Self.outline)
        let summary = try Self.summary(from: "B", to: "D", in: &fixture)

        try expectUndoAndRedo(DeleteNodeCommand(nodeIDs: [fixture["B"], fixture["D"]]), on: &fixture)

        #expect(Self.members(summary.group, in: fixture) == ["C"])
    }

    @Test func deletingEveryMemberKeepsTheSummaryTopicAsALastChild() throws {
        var fixture = try GraphFixture(Self.outline)
        let summary = try Self.summary(from: "B", to: "C", in: &fixture)

        try expectUndoAndRedo(DeleteNodeCommand(nodeIDs: [fixture["B"], fixture["C"]]), on: &fixture)

        #expect(fixture.state.group(summary.group) == nil)
        #expect(fixture.state.childIDs(of: fixture["Root"]).last == summary.topic)
        #expect(fixture.state.runSiblingIDs(of: fixture["Root"]).contains(summary.topic))
    }

    @Test func movingAnEndToAnotherParentMovesItInward() throws {
        var fixture = try GraphFixture(Self.outline)
        let summary = try Self.summary(from: "B", to: "D", in: &fixture)

        try expectUndoAndRedo(ReparentNodeCommand(nodeID: fixture["D"], newParentID: fixture["A"]), on: &fixture)

        #expect(Self.members(summary.group, in: fixture) == ["B", "C"])
    }

    @Test func anEndReorderedPastTheOtherSwapsTheEnds() throws {
        var fixture = try GraphFixture(Self.outline)
        let summary = try Self.summary(from: "B", to: "C", in: &fixture)

        try expectUndoAndRedo(
            ReparentNodeCommand(nodeID: fixture["B"], newParentID: fixture["Root"], placement: .after(fixture["D"])),
            on: &fixture
        )

        #expect(Self.members(summary.group, in: fixture) == ["C", "D", "B"])
        #expect(GraphValidator.validate(fixture.state).isEmpty)
    }

    @Test func mergingAnEndMovesItInward() throws {
        var fixture = try GraphFixture(Self.outline)
        let summary = try Self.summary(from: "B", to: "D", in: &fixture)

        try expectUndoAndRedo(MergeNodesCommand(into: fixture["C"], merging: [fixture["D"]]), on: &fixture)

        #expect(Self.members(summary.group, in: fixture) == ["B", "C"])
        #expect(GraphValidator.validate(fixture.state).isEmpty)
    }

    @Test func movingTheSummaryTopicAwayDropsTheBracket() throws {
        var fixture = try GraphFixture(Self.outline)
        let summary = try Self.summary(from: "B", to: "C", in: &fixture)

        try expectUndoAndRedo(ReparentNodeCommand(nodeID: summary.topic, newParentID: fixture["A"]), on: &fixture)

        #expect(fixture.state.group(summary.group) == nil)
        #expect(fixture.state.node(summary.topic)?.parentID == fixture["A"])
    }

    @Test func duplicateCopiesASummaryInsideTheBranch() throws {
        var fixture = try GraphFixture(Self.outline)
        let summary = try Self.summary(from: "A1", to: "A1", in: &fixture)
        let copyID = NodeID()

        try expectUndoAndRedo(DuplicateBranchCommand(nodeID: fixture["A"], copyID: copyID), on: &fixture)

        let copy = try #require(fixture.state.groups.values.first { $0.id != summary.group })
        #expect(copy.kind == .summary)
        #expect(copy.parentNodeID == copyID)
        #expect(copy.summaryNodeID != summary.topic)
        #expect(copy.summaryNodeID.flatMap { fixture.state.node($0)?.parentID } == copyID)
        #expect(GraphValidator.validate(fixture.state).isEmpty)
    }
}

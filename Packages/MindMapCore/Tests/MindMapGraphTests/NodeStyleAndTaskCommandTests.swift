import Foundation
import MindMapDomain
@testable import MindMapGraph
import Testing

@Suite("Topic colour, symbol and task")
struct NodeStyleAndTaskCommandTests {
    static let outline = """
    Root
      A
      B
    """

    @Test func styleSetsColorAndSymbolOnEverySelectedTopic() throws {
        var fixture = try GraphFixture(Self.outline)

        try expectUndoAndRedo(
            SetNodeStyleCommand(nodeIDs: [fixture["A"], fixture["B"]], color: .set(.rose), symbol: .set(" 🚀🔥")),
            on: &fixture
        )

        for id in [fixture["A"], fixture["B"]] {
            #expect(fixture.state.node(id)?.color == .rose)
            #expect(fixture.state.node(id)?.symbol == "🚀")
        }
    }

    @Test func styleLeavesFieldsItIsNotGiven() throws {
        var fixture = try GraphFixture(Self.outline)
        try fixture.engine.execute(SetNodeStyleCommand(nodeIDs: [fixture["A"]], color: .set(.teal), symbol: .set("flag")))

        try expectUndoAndRedo(SetNodeStyleCommand(nodeIDs: [fixture["A"]], symbol: .set(nil)), on: &fixture)

        #expect(fixture.state.node(fixture["A"])?.color == .teal)
        #expect(fixture.state.node(fixture["A"])?.symbol == nil)
    }

    @Test func styleRefusesAMissingTopicAndChangesNothing() throws {
        var fixture = try GraphFixture(Self.outline)
        let before = fixture.state
        let ghost = NodeID()

        #expect(throws: GraphError.nodeNotFound(ghost)) {
            try fixture.engine.execute(SetNodeStyleCommand(nodeIDs: [fixture["A"], ghost], color: .set(.blue)))
        }
        #expect(fixture.state == before)
    }

    @Test func makeTaskThenDone() throws {
        var fixture = try GraphFixture(Self.outline)
        let due = try #require(CalendarDay(isoString: "2026-10-09"))

        try expectUndoAndRedo(
            SetTaskCommand(nodeIDs: [fixture["A"]], state: .set(.open), priority: .set(.high), due: .set(due)),
            on: &fixture
        )
        try expectUndoAndRedo(SetTaskCommand(nodeIDs: [fixture["A"]], state: .set(.done)), on: &fixture)

        let node = try #require(fixture.state.node(fixture["A"]))
        #expect(node.taskState == .done)
        #expect(node.priority == .high)
        #expect(node.dueDate == due)
        #expect(node.startDate == nil)
    }

    /// Remove Task keeps priority and dates, so Make Task again loses nothing.
    @Test func removingTheTaskKeepsPriorityAndDates() throws {
        var fixture = try GraphFixture(Self.outline)
        let start = try #require(CalendarDay(isoString: "2026-10-01"))
        try fixture.engine.execute(SetTaskCommand(nodeIDs: [fixture["A"]], state: .set(.open), priority: .set(.low), start: .set(start)))

        try expectUndoAndRedo(SetTaskCommand(nodeIDs: [fixture["A"]], state: .set(nil)), on: &fixture)

        let node = try #require(fixture.state.node(fixture["A"]))
        #expect(node.taskState == nil)
        #expect(node.priority == .low)
        #expect(node.startDate == start)
    }

    @Test func settingCurrentValuesIsNotAnUndoStep() throws {
        var fixture = try GraphFixture(Self.outline)
        try fixture.engine.execute(SetTaskCommand(nodeIDs: [fixture["A"]], state: .set(.open)))

        let changes = try fixture.engine.execute(SetTaskCommand(nodeIDs: [fixture["A"]], state: .set(.open)))

        #expect(changes.isEmpty)
    }

    @Test func duplicateBranchCopiesStyleTaskAndTags() throws {
        var fixture = try GraphFixture(Self.outline)
        try fixture.engine.execute(SetNodeStyleCommand(nodeIDs: [fixture["A"]], color: .set(.amber), symbol: .set("star")))
        try fixture.engine.execute(SetTaskCommand(nodeIDs: [fixture["A"]], state: .set(.done), priority: .set(.medium)))
        try fixture.engine.execute(TagNodesCommand(nodeIDs: [fixture["A"]], add: [.named("Việc")]))
        let copyID = NodeID()

        try expectUndoAndRedo(DuplicateBranchCommand(nodeID: fixture["A"], copyID: copyID), on: &fixture)

        let original = try #require(fixture.state.node(fixture["A"]))
        let copy = try #require(fixture.state.node(copyID))
        #expect(copy.color == original.color)
        #expect(copy.symbol == original.symbol)
        #expect(copy.taskState == original.taskState)
        #expect(copy.priority == original.priority)
        #expect(fixture.state.tags(of: copyID).map(\.name) == ["Việc"])
    }
}

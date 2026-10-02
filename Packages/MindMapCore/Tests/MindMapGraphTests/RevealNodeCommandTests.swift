import Foundation
import MindMapDomain
@testable import MindMapGraph
import Testing

@Suite("Revealing a topic")
struct RevealNodeCommandTests {
    static func fixture() throws -> GraphFixture {
        var fixture = try GraphFixture("""
        Root
          A
            A1
              A1a
          B
            B1
        """)
        try fixture.engine.execute(UpdateNodeCommand(nodeID: fixture["A1"], .isCollapsed(true)))
        try fixture.engine.execute(UpdateNodeCommand(nodeID: fixture["A"], .isCollapsed(true)))
        try fixture.engine.execute(UpdateNodeCommand(nodeID: fixture["B"], .isCollapsed(true)))
        return fixture
    }

    @Test func opensEveryCollapsedAncestorAndNothingElse() throws {
        var fixture = try Self.fixture()
        #expect(RevealNodeCommand.isHidden(fixture["A1a"], in: fixture.state))

        try fixture.engine.execute(RevealNodeCommand(nodeID: fixture["A1a"]))

        #expect(!RevealNodeCommand.isHidden(fixture["A1a"], in: fixture.state))
        #expect(fixture.state.node(fixture["A"])?.isCollapsed == false)
        #expect(fixture.state.node(fixture["A1"])?.isCollapsed == false)
        #expect(fixture.state.node(fixture["B"])?.isCollapsed == true)
    }

    @Test func keepsTheTopicItselfCollapsed() throws {
        var fixture = try Self.fixture()

        try fixture.engine.execute(RevealNodeCommand(nodeID: fixture["A1"]))

        #expect(fixture.state.node(fixture["A1"])?.isCollapsed == true)
        #expect(fixture.outline.contains("    A1"))
    }

    @Test func visibleTopicIsANoOp() throws {
        var fixture = try Self.fixture()
        let undoable = fixture.engine.canUndo

        let changes = try fixture.engine.execute(RevealNodeCommand(nodeID: fixture["B"]))

        #expect(changes.isEmpty)
        #expect(fixture.engine.canUndo == undoable)
    }

    @Test func unknownTopicIsRefused() throws {
        var fixture = try Self.fixture()
        let before = fixture.state

        #expect(throws: GraphError.self) {
            try fixture.engine.execute(RevealNodeCommand(nodeID: NodeID()))
        }
        #expect(fixture.state == before)
    }

    @Test func undoRestoresAndRedoReapplies() throws {
        var fixture = try Self.fixture()
        let before = fixture.state

        try fixture.engine.execute(RevealNodeCommand(nodeID: fixture["A1a"]))
        let after = fixture.state

        fixture.engine.undo()
        #expect(sameContent(fixture.state, before))
        #expect(RevealNodeCommand.isHidden(fixture["A1a"], in: fixture.state))
        fixture.engine.redo()
        #expect(sameContent(fixture.state, after))
    }
}

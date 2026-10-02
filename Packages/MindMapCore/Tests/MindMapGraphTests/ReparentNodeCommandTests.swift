import Foundation
import MindMapDomain
@testable import MindMapGraph
import Testing

@Suite("Reparenting nodes")
struct ReparentNodeCommandTests {
    @Test func movesTheBranchUnderANewParent() throws {
        var fixture = try GraphFixture("""
        Root
          A
            A1
          B
        """)

        try fixture.engine.execute(ReparentNodeCommand(nodeID: fixture["A"], newParentID: fixture["B"]))

        #expect(fixture.outline == """
        Root
          B
            A
              A1
        """)
    }

    @Test func reordersWithinTheSameParent() throws {
        var fixture = try GraphFixture("""
        Root
          A
          B
          C
        """)

        try fixture.engine.execute(ReparentNodeCommand(nodeID: fixture["C"], newParentID: fixture["Root"], placement: .first))
        try fixture.engine.execute(ReparentNodeCommand(nodeID: fixture["A"], newParentID: fixture["Root"], placement: .after(fixture["B"])))

        #expect(fixture.childTitles(of: "Root") == ["C", "B", "A"])
    }

    @Test func movingUnderItsOwnDescendantIsRefused() throws {
        var fixture = try GraphFixture("""
        Root
          A
            A1
              A1a
        """)
        let before = fixture.state

        #expect(throws: GraphError.wouldCreateCycle(node: fixture["A"], newParent: fixture["A1a"])) {
            try fixture.engine.execute(ReparentNodeCommand(nodeID: fixture["A"], newParentID: fixture["A1a"]))
        }
        #expect(fixture.state == before)
    }

    @Test func movingUnderItselfIsRefused() throws {
        var fixture = try GraphFixture("""
        Root
          A
        """)

        #expect(throws: GraphError.wouldCreateCycle(node: fixture["A"], newParent: fixture["A"])) {
            try fixture.engine.execute(ReparentNodeCommand(nodeID: fixture["A"], newParentID: fixture["A"]))
        }
    }

    @Test func theRootCannotMove() throws {
        var fixture = try GraphFixture("""
        Root
          A
        """)

        #expect(throws: GraphError.cannotMoveRoot) {
            try fixture.engine.execute(ReparentNodeCommand(nodeID: fixture["Root"], newParentID: fixture["A"]))
        }
    }

    @Test func onlyTheMovedNodeChanges() throws {
        var fixture = try GraphFixture("""
        Root
          A
          B
          C
        """)

        let changes = try fixture.engine.execute(ReparentNodeCommand(nodeID: fixture["C"], newParentID: fixture["Root"], placement: .before(fixture["B"])))

        // One record per move keeps sync traffic and conflicts small.
        #expect(Set(changes.nodes.keys) == [fixture["C"]])
    }
}

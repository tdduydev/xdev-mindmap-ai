import Foundation
import MindMapDomain
@testable import MindMapGraph
import Testing

@Suite("Updating nodes")
struct UpdateNodeCommandTests {
    @Test func changesTitleAndNote() throws {
        var fixture = try GraphFixture("""
        Root
          A
        """)

        try fixture.engine.execute(UpdateNodeCommand(nodeID: fixture["A"], changes: [.title("Alpha"), .note("Why it matters")]))

        let node = try #require(fixture.state.node(fixture["A"]))
        #expect(node.title == "Alpha")
        #expect(node.note == "Why it matters")
    }

    @Test func settingTheSameValueIsNotAnUndoStep() throws {
        var fixture = try GraphFixture("""
        Root
          A
        """)
        fixture.engine.undo()
        #expect(fixture.engine.canRedo)

        let changes = try fixture.engine.execute(UpdateNodeCommand(nodeID: fixture["Root"], .title("Root")))

        #expect(changes.isEmpty)
        // A no-op must not wipe the redo stack either.
        #expect(fixture.engine.canRedo)
    }

    @Test func bumpsUpdatedAtOnlyOnTheEditedNode() throws {
        let clock = TestClock()
        var fixture = try GraphFixture("""
        Root
          A
          B
        """, clock: clock)
        let before = try #require(fixture.state.node(fixture["B"]))

        try fixture.engine.execute(UpdateNodeCommand(nodeID: fixture["A"], .title("Alpha")))

        #expect(fixture.state.node(fixture["A"])?.updatedAt == clock.now)
        #expect(fixture.state.node(fixture["B"]) == before)
    }

    @Test func unknownNodeIsRefused() throws {
        var fixture = try GraphFixture("Root")
        let ghost = NodeID()

        #expect(throws: GraphError.nodeNotFound(ghost)) {
            try fixture.engine.execute(UpdateNodeCommand(nodeID: ghost, .title("X")))
        }
    }
}

@Suite("Deleting nodes")
struct DeleteNodeCommandTests {
    @Test func deletesTheWholeBranch() throws {
        var fixture = try GraphFixture("""
        Root
          A
            A1
              A1a
          B
        """)

        let changes = try fixture.engine.execute(DeleteNodeCommand(nodeID: fixture["A"]))

        #expect(fixture.outline == "Root\n  B")
        #expect(Set(changes.deletedNodeIDs) == [fixture["A"], fixture["A1"], fixture["A1a"]])
    }

    @Test func removesEdgesThatTouchDeletedNodes() throws {
        var fixture = try GraphFixture("""
        Root
          A
            A1
          B
        """)
        let mapID = fixture.state.map.id
        let toDeleted = MindEdge(mapID: mapID, sourceNodeID: fixture["B"], targetNodeID: fixture["A1"])
        let kept = MindEdge(mapID: mapID, sourceNodeID: fixture["B"], targetNodeID: fixture["Root"])
        try fixture.engine.execute(InsertEdgesForTest(edges: [toDeleted, kept]))

        try fixture.engine.execute(DeleteNodeCommand(nodeID: fixture["A"]))

        #expect(Set(fixture.state.edges.keys) == [kept.id])
    }

    @Test func selectionInsideAnotherSelectedBranchIsFine() throws {
        var fixture = try GraphFixture("""
        Root
          A
            A1
          B
        """)

        try fixture.engine.execute(DeleteNodeCommand(nodeIDs: [fixture["A1"], fixture["A"]]))

        #expect(fixture.outline == "Root\n  B")
    }

    @Test func deletingTheRootEmptiesTheMap() throws {
        var fixture = try GraphFixture("""
        Root
          A
        """)

        try fixture.engine.execute(DeleteNodeCommand(nodeID: fixture["Root"]))

        #expect(fixture.state.isEmpty)
        #expect(fixture.state.map.rootNodeID == nil)
    }

    @Test func unknownNodeIsRefusedAndNothingIsDeleted() throws {
        var fixture = try GraphFixture("""
        Root
          A
        """)
        let before = fixture.state
        let ghost = NodeID()

        #expect(throws: GraphError.nodeNotFound(ghost)) {
            try fixture.engine.execute(DeleteNodeCommand(nodeIDs: [fixture["A"], ghost]))
        }
        #expect(fixture.state == before)
    }
}

/// Edges have no public command yet (relationships arrive in a later phase),
/// so tests insert them through the transaction directly.
struct InsertEdgesForTest: GraphCommand {
    let edges: [MindEdge]

    func execute(in transaction: inout GraphTransaction) throws {
        for edge in edges {
            try transaction.insertEdge(edge)
        }
    }
}

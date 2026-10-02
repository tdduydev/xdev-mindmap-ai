import Foundation
import MindMapDomain
@testable import MindMapGraph
import Testing

@Suite("Adding nodes")
struct AddNodeCommandTests {
    @Test func addRootSetsTheMapRoot() throws {
        var engine = try GraphEngine(state: GraphState(map: MindMap(title: "Plan")))
        let rootID = NodeID()

        try engine.execute(AddNodeCommand(nodeID: rootID, .root, title: "Plan"))

        #expect(engine.state.map.rootNodeID == rootID)
        #expect(engine.state.root?.parentID == nil)
    }

    @Test func secondRootIsRefused() throws {
        var fixture = try GraphFixture("Root")

        #expect(throws: GraphError.rootAlreadyExists) {
            try fixture.engine.execute(AddNodeCommand(.root, title: "Another"))
        }
    }

    @Test func childrenAppendInOrder() throws {
        let fixture = try GraphFixture("""
        Root
          A
          B
          C
        """)

        #expect(fixture.childTitles(of: "Root") == ["A", "B", "C"])
    }

    @Test func placementPutsChildrenWhereAsked() throws {
        var fixture = try GraphFixture("""
        Root
          A
          C
        """)
        let root = fixture["Root"]

        try fixture.engine.execute(AddNodeCommand(.child(of: root, at: .first), title: "First"))
        try fixture.engine.execute(AddNodeCommand(.child(of: root, at: .before(fixture["C"])), title: "B"))
        try fixture.engine.execute(AddNodeCommand(.child(of: root, at: .after(fixture["C"])), title: "D"))

        #expect(fixture.childTitles(of: "Root") == ["First", "A", "B", "C", "D"])
    }

    @Test func siblingGoesRightAfterItsAnchor() throws {
        var fixture = try GraphFixture("""
        Root
          A
          C
        """)

        try fixture.engine.execute(AddNodeCommand(.sibling(after: fixture["A"]), title: "B"))

        #expect(fixture.childTitles(of: "Root") == ["A", "B", "C"])
    }

    @Test func rootHasNoSiblings() throws {
        var fixture = try GraphFixture("Root")

        #expect(throws: GraphError.rootHasNoSiblings) {
            try fixture.engine.execute(AddNodeCommand(.sibling(after: fixture["Root"]), title: "X"))
        }
    }

    @Test func missingParentIsRefused() throws {
        var fixture = try GraphFixture("Root")
        let ghost = NodeID()

        #expect(throws: GraphError.nodeNotFound(ghost)) {
            try fixture.engine.execute(AddNodeCommand(.child(of: ghost), title: "X"))
        }
    }

    @Test func duplicateIDIsRefused() throws {
        var fixture = try GraphFixture("""
        Root
          A
        """)
        let existing = fixture["A"]

        #expect(throws: GraphError.nodeAlreadyExists(existing)) {
            try fixture.engine.execute(AddNodeCommand(nodeID: existing, .child(of: fixture["Root"]), title: "Again"))
        }
    }

    @Test func anchorFromAnotherParentIsRefused() throws {
        var fixture = try GraphFixture("""
        Root
          A
            A1
          B
        """)
        let a1 = fixture["A1"]

        #expect(throws: GraphError.invalidPlacementAnchor(a1)) {
            try fixture.engine.execute(AddNodeCommand(.child(of: fixture["B"], at: .after(a1)), title: "X"))
        }
    }

    @Test func addingIntoACollapsedBranchOpensIt() throws {
        var fixture = try GraphFixture("""
        Root
          A
            A1
        """)
        try fixture.engine.execute(UpdateNodeCommand(nodeID: fixture["A"], .isCollapsed(true)))

        try fixture.engine.execute(AddNodeCommand(.child(of: fixture["A"]), title: "A2"))

        #expect(fixture.state.node(fixture["A"])?.isCollapsed == false)
        fixture.engine.undo()
        #expect(fixture.state.node(fixture["A"])?.isCollapsed == true)
    }

    /// Typing a long list in the middle of a branch inserts after the newest
    /// node every time, which exhausts `Double` midpoints after ~50 steps.
    @Test func manyInsertsAtOneSpotKeepOrder() throws {
        var fixture = try GraphFixture("""
        Root
          Start
          End
        """)
        var previous = fixture["Start"]
        var expected = ["Start"]
        for index in 1...200 {
            let id = NodeID()
            try fixture.engine.execute(AddNodeCommand(nodeID: id, .sibling(after: previous), title: "\(index)"))
            previous = id
            expected.append("\(index)")
        }
        expected.append("End")

        #expect(fixture.childTitles(of: "Root") == expected)
        let keys = fixture.state.children(of: fixture["Root"]).map(\.sortOrder)
        #expect(Set(keys).count == keys.count)
    }

    @Test func newNodeIsStampedWithTheEngineClock() throws {
        let clock = TestClock()
        var fixture = try GraphFixture("Root", clock: clock)
        let id = NodeID()

        try fixture.engine.execute(AddNodeCommand(nodeID: id, .child(of: fixture["Root"]), title: "A"))

        let node = try #require(fixture.state.node(id))
        #expect(node.createdAt == clock.now)
        #expect(node.updatedAt == clock.now)
        #expect(fixture.state.map.updatedAt == clock.now)
    }
}

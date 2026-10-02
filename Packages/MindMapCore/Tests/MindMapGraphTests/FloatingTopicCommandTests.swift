import Foundation
import MindMapDomain
@testable import MindMapGraph
import Testing

@Suite("Floating topic commands")
struct FloatingTopicCommandTests {
    static func fixture() throws -> GraphFixture {
        try GraphFixture("""
        Root
          A
            A1
          B
          C
        """)
    }

    /// The central topic stays the one root, and the graph stays valid.
    static func expectOneCentralTopic(_ fixture: GraphFixture, root: NodeID, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(fixture.state.map.rootNodeID == root, sourceLocation: sourceLocation)
        #expect(GraphValidator.validate(fixture.state).isEmpty, sourceLocation: sourceLocation)
    }

    // MARK: Add

    @Test func addPutsATopicAtThePositionWithUndoAndRedo() throws {
        var fixture = try Self.fixture()
        let root = fixture["Root"]
        let before = fixture.state
        let id = NodeID()
        let position = TopicPosition(x: 400, y: -120)

        try fixture.engine.execute(AddFloatingTopicCommand(nodeID: id, title: "Idea", position: position), named: "Add Floating Topic")

        let node = try #require(fixture.state.node(id))
        #expect(node.parentID == nil)
        #expect(node.position == position)
        #expect(node.title == "Idea")
        #expect(fixture.state.floatingTopicIDs == [id])
        #expect(fixture.engine.history.undoNames == [nil, nil, nil, nil, nil, "Add Floating Topic"])
        Self.expectOneCentralTopic(fixture, root: root)

        fixture.engine.undo()
        #expect(sameContent(fixture.state, before))
        fixture.engine.redo()
        #expect(fixture.state.node(id)?.position == position)
        Self.expectOneCentralTopic(fixture, root: root)
    }

    @Test func addNeedsACentralTopic() throws {
        var engine = try GraphEngine(state: GraphState(map: MindMap(title: "Empty")))
        #expect(throws: GraphError.noCentralTopic) {
            try engine.execute(AddFloatingTopicCommand(title: "Idea", position: TopicPosition(x: 0, y: 0)))
        }
        #expect(engine.state.nodes.isEmpty)
        #expect(engine.state.map.rootNodeID == nil)
    }

    @Test func childrenOfAFloatingTopicAreOrdinary() throws {
        var fixture = try Self.fixture()
        let id = NodeID()
        try fixture.engine.execute(AddFloatingTopicCommand(nodeID: id, title: "Idea", position: TopicPosition(x: 0, y: 300)))
        let child = NodeID()
        try fixture.engine.execute(AddNodeCommand(nodeID: child, .child(of: id), title: "Detail"))

        #expect(fixture.state.node(child)?.position == nil)
        #expect(fixture.state.ancestors(of: child) == [id])
        // The floating topic has no siblings and no grandparent.
        #expect(throws: GraphError.rootHasNoSiblings) { try fixture.engine.execute(AddNodeCommand(.sibling(after: id), title: "X")) }
        #expect(throws: GraphError.alreadyTopLevel(child)) { try fixture.engine.execute(PromoteNodeCommand(nodeID: child)) }
        #expect(throws: GraphError.noPreviousSibling(id)) { try fixture.engine.execute(DemoteNodeCommand(nodeID: id)) }
        Self.expectOneCentralTopic(fixture, root: fixture["Root"])
    }

    // MARK: Move

    @Test func moveChangesOnlyThePositionWithUndoAndRedo() throws {
        var fixture = try Self.fixture()
        let id = NodeID()
        let start = TopicPosition(x: 400, y: -120)
        let end = TopicPosition(x: -260, y: 90.5)
        try fixture.engine.execute(AddFloatingTopicCommand(nodeID: id, title: "Idea", position: start))
        let child = NodeID()
        try fixture.engine.execute(AddNodeCommand(nodeID: child, .child(of: id), title: "Detail"))

        let changes = try fixture.engine.execute(MoveFloatingTopicCommand(nodeID: id, to: end), named: "Move Topic")

        #expect(Set(changes.nodes.keys) == [id])
        #expect(fixture.state.node(id)?.position == end)
        #expect(fixture.state.node(child)?.parentID == id)
        fixture.engine.undo()
        #expect(fixture.state.node(id)?.position == start)
        fixture.engine.redo()
        #expect(fixture.state.node(id)?.position == end)
        Self.expectOneCentralTopic(fixture, root: fixture["Root"])
    }

    @Test func moveRefusesTopicsThatAreNotFloating() throws {
        var fixture = try Self.fixture()
        let position = TopicPosition(x: 10, y: 10)
        #expect(throws: GraphError.notFloating(fixture["A"])) {
            try fixture.engine.execute(MoveFloatingTopicCommand(nodeID: fixture["A"], to: position))
        }
        #expect(throws: GraphError.notFloating(fixture["Root"])) {
            try fixture.engine.execute(MoveFloatingTopicCommand(nodeID: fixture["Root"], to: position))
        }
        #expect(fixture.state.node(fixture["Root"])?.position == nil)
    }

    @Test func movingToTheSamePlaceRecordsNothing() throws {
        var fixture = try Self.fixture()
        let id = NodeID()
        let position = TopicPosition(x: 5, y: 5)
        try fixture.engine.execute(AddFloatingTopicCommand(nodeID: id, title: "Idea", position: position))
        let changes = try fixture.engine.execute(MoveFloatingTopicCommand(nodeID: id, to: position))
        #expect(changes.isEmpty)
    }

    // MARK: Detach

    @Test func detachMakesABranchFloatingWithUndoAndRedo() throws {
        var fixture = try Self.fixture()
        let before = fixture.state
        let position = TopicPosition(x: 300, y: 260)

        try fixture.engine.execute(DetachBranchCommand(nodeID: fixture["A"], position: position), named: "Detach Topic")

        let detached = try #require(fixture.state.node(fixture["A"]))
        #expect(detached.parentID == nil)
        #expect(detached.position == position)
        #expect(fixture.state.node(fixture["A1"])?.parentID == fixture["A"])
        #expect(fixture.childTitles(of: "Root") == ["B", "C"])
        #expect(fixture.state.floatingTopicIDs == [fixture["A"]])
        Self.expectOneCentralTopic(fixture, root: fixture["Root"])

        fixture.engine.undo()
        #expect(sameContent(fixture.state, before))
        #expect(fixture.childTitles(of: "Root") == ["A", "B", "C"])
        fixture.engine.redo()
        #expect(fixture.state.node(fixture["A"])?.position == position)
        #expect(fixture.state.floatingTopicIDs == [fixture["A"]])
    }

    /// A boundary the topic ended shrinks, and undo restores it with the topic.
    @Test func detachShrinksTheBoundaryItEndedAndUndoRestoresIt() throws {
        var fixture = try Self.fixture()
        let group = GroupID()
        try fixture.engine.execute(AddGroupCommand(groupID: group, from: fixture["A"], to: fixture["C"]))
        let boundary = try #require(fixture.state.groups[group])

        try fixture.engine.execute(DetachBranchCommand(nodeID: fixture["A"], position: TopicPosition(x: 0, y: 400)))
        #expect(fixture.state.groups[group]?.firstNodeID == fixture["B"])

        fixture.engine.undo()
        #expect(fixture.state.groups[group] == boundary)
        fixture.engine.redo()
        #expect(fixture.state.groups[group]?.firstNodeID == fixture["B"])
        #expect(GraphValidator.validate(fixture.state).isEmpty)
    }

    @Test func detachRefusesTheCentralTopicAndFloatingTopics() throws {
        var fixture = try Self.fixture()
        let position = TopicPosition(x: 1, y: 1)
        #expect(throws: GraphError.cannotMoveRoot) {
            try fixture.engine.execute(DetachBranchCommand(nodeID: fixture["Root"], position: position))
        }
        let id = NodeID()
        try fixture.engine.execute(AddFloatingTopicCommand(nodeID: id, title: "Idea", position: position))
        #expect(throws: GraphError.notInTree(id)) {
            try fixture.engine.execute(DetachBranchCommand(nodeID: id, position: position))
        }
        let missing = NodeID()
        #expect(throws: GraphError.nodeNotFound(missing)) {
            try fixture.engine.execute(DetachBranchCommand(nodeID: missing, position: position))
        }
    }

    // MARK: Attach

    /// Attaching is a reparent: the position goes in the same step, and undo
    /// brings it back.
    @Test func attachThroughReparentClearsThePositionWithUndoAndRedo() throws {
        var fixture = try Self.fixture()
        let id = NodeID()
        let position = TopicPosition(x: -500, y: 40)
        try fixture.engine.execute(AddFloatingTopicCommand(nodeID: id, title: "Idea", position: position))
        let child = NodeID()
        try fixture.engine.execute(AddNodeCommand(nodeID: child, .child(of: id), title: "Detail"))

        let changes = try fixture.engine.execute(
            ReparentNodeCommand(nodeID: id, newParentID: fixture["B"], placement: .last),
            named: "Move Topic"
        )

        #expect(Set(changes.nodes.keys) == [id])
        let attached = try #require(fixture.state.node(id))
        #expect(attached.parentID == fixture["B"])
        #expect(attached.position == nil)
        #expect(fixture.state.floatingTopicIDs.isEmpty)
        #expect(fixture.state.node(child)?.parentID == id)
        Self.expectOneCentralTopic(fixture, root: fixture["Root"])

        fixture.engine.undo()
        #expect(fixture.state.node(id)?.parentID == nil)
        #expect(fixture.state.node(id)?.position == position)
        #expect(fixture.state.floatingTopicIDs == [id])
        fixture.engine.redo()
        #expect(fixture.state.node(id)?.parentID == fixture["B"])
        #expect(fixture.state.node(id)?.position == nil)
    }

    @Test func attachRefusesItsOwnBranch() throws {
        var fixture = try Self.fixture()
        let id = NodeID()
        try fixture.engine.execute(AddFloatingTopicCommand(nodeID: id, title: "Idea", position: TopicPosition(x: 0, y: 0)))
        let child = NodeID()
        try fixture.engine.execute(AddNodeCommand(nodeID: child, .child(of: id), title: "Detail"))
        #expect(throws: GraphError.wouldCreateCycle(node: id, newParent: child)) {
            try fixture.engine.execute(ReparentNodeCommand(nodeID: id, newParentID: child))
        }
    }

    /// Deleting a floating topic deletes its branch; undo restores both.
    @Test func deleteRemovesTheFloatingBranch() throws {
        var fixture = try Self.fixture()
        let id = NodeID()
        try fixture.engine.execute(AddFloatingTopicCommand(nodeID: id, title: "Idea", position: TopicPosition(x: 0, y: 200)))
        let child = NodeID()
        try fixture.engine.execute(AddNodeCommand(nodeID: child, .child(of: id), title: "Detail"))
        let before = fixture.state

        try fixture.engine.execute(DeleteNodeCommand(nodeID: id))
        #expect(fixture.state.node(id) == nil)
        #expect(fixture.state.node(child) == nil)
        Self.expectOneCentralTopic(fixture, root: fixture["Root"])
        fixture.engine.undo()
        #expect(sameContent(fixture.state, before))
        fixture.engine.redo()
        #expect(fixture.state.node(id) == nil)
    }

    // MARK: Reading order

    /// Floating branches come after the main tree, oldest first, at the level
    /// they are drawn at.
    @Test func outlineAndReadingOrderListFloatingBranchesAfterTheTree() throws {
        var fixture = try Self.fixture()
        let first = NodeID()
        let second = NodeID()
        let child = NodeID()
        try fixture.engine.execute(AddFloatingTopicCommand(nodeID: first, title: "First", position: TopicPosition(x: 0, y: 900)))
        try fixture.engine.execute(AddFloatingTopicCommand(nodeID: second, title: "Second", position: TopicPosition(x: 0, y: -900)))
        try fixture.engine.execute(AddNodeCommand(nodeID: child, .child(of: first), title: "Detail"))

        #expect(fixture.state.topLevelIDs == [fixture["Root"], first, second])
        #expect(fixture.outline == """
        Root
          A
            A1
          B
          C
          First
            Detail
          Second
        """)
        let order = fixture.state.readingOrder()
        #expect(order.map(\.id) == fixture.state.visibleOutline().map(\.nodeID))
        #expect(order.map(\.depth) == [0, 1, 2, 1, 1, 1, 2, 1])

        try fixture.engine.execute(UpdateNodeCommand(nodeID: first, .isCollapsed(true)))
        #expect(!fixture.state.visibleOutline().map(\.nodeID).contains(child))
        #expect(fixture.state.readingOrder().map(\.id).contains(child))
    }
}

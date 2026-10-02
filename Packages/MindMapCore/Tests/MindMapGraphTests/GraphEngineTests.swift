import Foundation
import MindMapDomain
@testable import MindMapGraph
import Testing

@Suite("Undo and redo")
struct UndoRedoTests {
    static let base = """
    Root
      A
        A1
      B
        B1
      C
    """

    /// Every command kind, so a regression in any one of them shows up here.
    static func commands(for fixture: GraphFixture) -> [(String, any GraphCommand)] {
        [
            ("add child", AddNodeCommand(.child(of: fixture["A"]), title: "A2")),
            ("add sibling", AddNodeCommand(.sibling(after: fixture["A"]), title: "A+")),
            ("rename", UpdateNodeCommand(nodeID: fixture["B"], .title("Beta"))),
            ("collapse", UpdateNodeCommand(nodeID: fixture["B"], .isCollapsed(true))),
            ("delete branch", DeleteNodeCommand(nodeID: fixture["A"])),
            ("reparent", ReparentNodeCommand(nodeID: fixture["B"], newParentID: fixture["A1"])),
            ("reorder", ReparentNodeCommand(nodeID: fixture["C"], newParentID: fixture["Root"], placement: .first)),
        ]
    }

    @Test func undoRestoresAndRedoReapplies() throws {
        let template = try GraphFixture(Self.base)
        for (name, command) in Self.commands(for: template) {
            var fixture = template
            let before = fixture.state

            try fixture.engine.execute(command)
            let after = fixture.state

            fixture.engine.undo()
            #expect(sameContent(fixture.state, before), "undo of \(name)")
            fixture.engine.redo()
            #expect(sameContent(fixture.state, after), "redo of \(name)")
        }
    }

    @Test func undoRunsBackThroughSeveralSteps() throws {
        var fixture = try GraphFixture(Self.base)
        let start = fixture.state
        for (_, command) in Self.commands(for: fixture).prefix(4) {
            try fixture.engine.execute(command)
        }

        while fixture.engine.canUndo {
            fixture.engine.undo()
        }

        // The fixture's own adds are in history too, so undoing everything empties the map.
        #expect(fixture.state.isEmpty)
        while fixture.engine.canRedo {
            fixture.engine.redo()
        }
        for _ in 0..<4 {
            fixture.engine.undo()
        }
        #expect(sameContent(fixture.state, start))
    }

    @Test func newCommandClearsRedo() throws {
        var fixture = try GraphFixture(Self.base)
        try fixture.engine.execute(UpdateNodeCommand(nodeID: fixture["A"], .title("Alpha")))
        fixture.engine.undo()
        #expect(fixture.engine.canRedo)

        try fixture.engine.execute(UpdateNodeCommand(nodeID: fixture["B"], .title("Beta")))

        #expect(!fixture.engine.canRedo)
    }

    @Test func undoOfSiblingRenumberingRestoresEveryKey() throws {
        var fixture = try GraphFixture("""
        Root
          Start
          End
        """)
        var previous = fixture["Start"]
        for index in 1...200 {
            let before = fixture.state
            let id = NodeID()
            let changes = try fixture.engine.execute(AddNodeCommand(nodeID: id, .sibling(after: previous), title: "\(index)"))
            previous = id
            // More than the new node changed: this insert found no gap and renumbered its siblings.
            guard changes.nodes.count > 1 else { continue }

            fixture.engine.undo()
            #expect(sameContent(fixture.state, before))
            return
        }
        Issue.record("200 inserts at one spot never renumbered the siblings")
    }

    @Test func historyIsCapped() throws {
        var engine = try GraphEngine(state: GraphState.newMap(title: "Capped"), historyLimit: 3)
        let rootID = try #require(engine.state.map.rootNodeID)
        for index in 1...5 {
            try engine.execute(UpdateNodeCommand(nodeID: rootID, .title("v\(index)")))
        }

        var undone = 0
        while engine.undo() != nil {
            undone += 1
        }

        #expect(undone == 3)
        #expect(engine.state.root?.title == "v2")
    }

    @Test func undoWithEmptyHistoryDoesNothing() throws {
        var engine = try GraphEngine(state: GraphState.newMap(title: "Fresh"))
        let before = engine.state

        #expect(engine.undo() == nil)
        #expect(engine.redo() == nil)
        #expect(engine.state == before)
    }
}

@Suite("Engine guarantees")
struct GraphEngineTests {
    @Test func batchIsAllOrNothing() throws {
        var fixture = try GraphFixture("""
        Root
          A
        """)
        let before = fixture.state
        let ghost = NodeID()

        #expect(throws: GraphError.nodeNotFound(ghost)) {
            try fixture.engine.execute(BatchCommand([
                UpdateNodeCommand(nodeID: fixture["A"], .title("Changed")),
                AddNodeCommand(.child(of: ghost), title: "Fails"),
            ]))
        }
        #expect(fixture.state == before)
    }

    @Test func batchIsOneUndoStep() throws {
        var fixture = try GraphFixture("""
        Root
          A
        """)
        let before = fixture.state

        try fixture.engine.execute(BatchCommand([
            AddNodeCommand(.child(of: fixture["A"]), title: "A1"),
            AddNodeCommand(.child(of: fixture["A"]), title: "A2"),
            UpdateNodeCommand(nodeID: fixture["Root"], .title("Renamed")),
        ]))
        fixture.engine.undo()

        #expect(sameContent(fixture.state, before))
    }

    @Test func commandThatBreaksTheGraphIsRejected() throws {
        var fixture = try GraphFixture("""
        Root
          A
        """)
        let before = fixture.state

        #expect(throws: GraphError.self) {
            try fixture.engine.execute(DetachForTest(nodeID: fixture["A"]))
        }
        #expect(fixture.state == before)
        #expect(fixture.engine.canUndo)
    }

    @Test func invalidStartingGraphIsRejected() throws {
        let map = MindMap(title: "Broken")
        let orphan = MindNode(mapID: map.id, parentID: NodeID(), title: "Lost")

        #expect(throws: GraphError.self) {
            try GraphEngine(state: GraphState(map: map, nodes: [orphan], edges: []))
        }
    }

    @Test func changeSetDescribesExactlyWhatChanged() throws {
        var fixture = try GraphFixture("""
        Root
          A
        """)
        let newID = NodeID()

        let changes = try fixture.engine.execute(BatchCommand([
            AddNodeCommand(nodeID: newID, .child(of: fixture["A"]), title: "Temp"),
            DeleteNodeCommand(nodeID: newID),
            UpdateNodeCommand(nodeID: fixture["A"], .title("Alpha")),
        ]))

        // Created and deleted in one step cancels out; only the rename is left to save.
        #expect(Set(changes.nodes.keys) == [fixture["A"]])
        #expect(changes.savedNodes.map(\.title) == ["Alpha"])
        #expect(changes.deletedNodeIDs.isEmpty)
    }

    @Test func handlesAThousandNodes() throws {
        var engine = try GraphEngine(state: GraphState.newMap(title: "Large"))
        let rootID = try #require(engine.state.map.rootNodeID)
        var branches: [NodeID] = []
        for branch in 0..<20 {
            let id = NodeID()
            try engine.execute(AddNodeCommand(nodeID: id, .child(of: rootID), title: "Branch \(branch)"))
            branches.append(id)
        }
        var leaves = 0
        for branch in branches {
            for leaf in 0..<49 {
                try engine.execute(AddNodeCommand(.child(of: branch), title: "Leaf \(leaf)"))
                leaves += 1
            }
        }

        #expect(engine.state.nodes.count == 1 + branches.count + leaves)
        #expect(engine.state.visibleOutline().count == engine.state.nodes.count)
        try engine.execute(ReparentNodeCommand(nodeID: branches[0], newParentID: branches[1]))
        #expect(engine.state.depth(of: branches[0]) == 2)
    }
}

/// Clears a node's parent behind the engine's back, which leaves it detached.
struct DetachForTest: GraphCommand {
    let nodeID: NodeID

    func execute(in transaction: inout GraphTransaction) throws {
        try transaction.updateNode(nodeID) { $0.parentID = nil }
    }
}

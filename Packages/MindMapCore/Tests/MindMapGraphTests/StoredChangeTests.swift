import Foundation
import MindMapDomain
@testable import MindMapGraph
import Testing

/// `GraphEngine.takeStored`: a change from outside (another device through
/// iCloud) lands in an open map, and undo keeps only the steps it did not
/// touch (FR-SYN-04, FR-UND-05).
@Suite("Changes from outside")
struct StoredChangeTests {
    static let base = """
    Root
      A
        A1
      B
      C
    """

    let fixture: GraphFixture
    let clock = TestClock()
    /// The open map, with no history from building the fixture.
    var local: GraphEngine

    init() throws {
        fixture = try GraphFixture(Self.base)
        local = try GraphEngine(state: fixture.state, clock: clock.ticking)
    }

    /// The same map edited on another device, from the state the editor has now.
    private func remote(_ edit: (inout GraphEngine) throws -> Void) throws -> GraphState {
        var other = local
        try edit(&other)
        return other.state
    }

    private func rename(_ title: String, to newTitle: String) -> UpdateNodeCommand {
        UpdateNodeCommand(nodeID: fixture[title], .title(newTitle))
    }

    @Test mutating func theSameStateChangesNothing() throws {
        try local.execute(rename("B", to: "Beta"), named: "Rename")

        let result = try local.takeStored(local.state, now: clock.now)

        #expect(result.changes.isEmpty)
        #expect(!result.historyChanged)
        #expect(local.undoStepNames == ["Rename"])
    }

    @Test mutating func aRemoteEditShowsAndReportsWhatChanged() throws {
        let stored = try remote { try $0.execute(rename("C", to: "Gamma")) }

        let result = try local.takeStored(stored, now: clock.now)

        #expect(local.state.node(fixture["C"])?.title == "Gamma")
        #expect(Set(result.changes.nodes.keys) == [fixture["C"]])
    }

    @Test mutating func stepsTouchingTheRemoteTopicGoAndTheRestStay() throws {
        try local.execute(rename("B", to: "Beta"), named: "Rename B")
        try local.execute(rename("C", to: "Local C"), named: "Rename C")
        let stored = try remote { try $0.execute(rename("C", to: "Remote C")) }

        let result = try local.takeStored(stored, now: clock.now)

        #expect(result.droppedSteps == 1)
        #expect(result.historyChanged)
        #expect(local.undoStepNames == ["Rename B"])
        #expect(local.state.node(fixture["C"])?.title == "Remote C")

        // Undo and redo of the kept step leave the remote topic alone.
        local.undo()
        #expect(local.state.node(fixture["B"])?.title == "B")
        #expect(local.state.node(fixture["C"])?.title == "Remote C")
        local.redo()
        #expect(local.state.node(fixture["B"])?.title == "Beta")
        #expect(local.state.node(fixture["C"])?.title == "Remote C")
    }

    @Test mutating func untouchedHistoryKeepsRedoToo() throws {
        try local.execute(rename("B", to: "Beta"), named: "Rename B")
        local.undo()
        let stored = try remote { try $0.execute(rename("C", to: "Remote C")) }

        let result = try local.takeStored(stored, now: clock.now)

        #expect(!result.historyChanged)
        #expect(local.canRedo)
        local.redo()
        #expect(local.state.node(fixture["B"])?.title == "Beta")
    }

    @Test mutating func aRedoStepOnTheRemoteTopicEmptiesRedoOnly() throws {
        try local.execute(rename("B", to: "Beta"), named: "Rename B")
        try local.execute(rename("C", to: "Local C"), named: "Rename C")
        local.undo()
        let stored = try remote { try $0.execute(rename("C", to: "Remote C")) }

        let result = try local.takeStored(stored, now: clock.now)

        #expect(result.droppedSteps == 0)
        #expect(result.historyChanged)
        #expect(!local.canRedo)
        #expect(local.undoStepNames == ["Rename B"])
    }

    /// Undoing the add of A1's parent while A1's own add is gone would leave a
    /// topic without its parent, so both go.
    @Test mutating func aStepThatDependsOnADroppedOneGoesToo() throws {
        let newParent = NodeID()
        let newChild = NodeID()
        try local.execute(AddNodeCommand(nodeID: newParent, .child(of: fixture["B"]), title: "New"), named: "Add Parent")
        try local.execute(AddNodeCommand(nodeID: newChild, .child(of: newParent), title: "Child"), named: "Add Child")
        try local.execute(rename("C", to: "Local C"), named: "Rename C")
        let stored = try remote { try $0.execute(UpdateNodeCommand(nodeID: newChild, .title("Remote child"))) }

        let result = try local.takeStored(stored, now: clock.now)

        #expect(result.droppedSteps == 2)
        #expect(local.undoStepNames == ["Rename C"])
    }

    @Test mutating func aStepUnderATopicRenamedElsewhereStays() throws {
        try local.execute(AddNodeCommand(.child(of: fixture["B"]), title: "Under B"), named: "Add Topic")
        let stored = try remote { try $0.execute(rename("B", to: "Remote B")) }

        let result = try local.takeStored(stored, now: clock.now)

        #expect(result.droppedSteps == 0)
        #expect(local.undoStepNames == ["Add Topic"])
        local.undo()
        #expect(local.state.children(of: fixture["B"]).isEmpty)
        #expect(local.state.node(fixture["B"])?.title == "Remote B")
    }

    /// Another device deleted the branch a topic was just added under: the
    /// topic hangs under the root (nothing lost) and its add cannot be undone.
    @Test mutating func aTopicUnderADeletedBranchStaysAndItsStepGoes() throws {
        let added = NodeID()
        try local.execute(AddNodeCommand(nodeID: added, .child(of: fixture["A"]), title: "Added"), named: "Add Topic")
        var stored = try remote { try $0.execute(DeleteNodeCommand(nodeID: fixture["A"])) }
        // The other device never had the new topic; sync brings it in beside the delete.
        stored = GraphState(map: stored.map, nodes: Array(stored.nodes.values) + [try #require(local.state.node(added))], edges: [])

        let result = try local.takeStored(stored, now: clock.now)

        #expect(local.state.node(added)?.parentID == local.state.map.rootNodeID)
        #expect(local.state.node(fixture["A"]) == nil)
        #expect(result.droppedSteps == 1)
        #expect(!local.canUndo)
        #expect(GraphValidator.validate(local.state).isEmpty)
    }

    @Test mutating func aRemoteMapRenameDropsALocalMapRename() throws {
        try local.execute(RenameMapCommand(title: "Local"), named: "Rename Map")
        try local.execute(rename("B", to: "Beta"), named: "Rename B")
        let stored = try remote { try $0.execute(RenameMapCommand(title: "Remote")) }

        _ = try local.takeStored(stored, now: clock.now)

        #expect(local.state.map.title == "Remote")
        #expect(local.undoStepNames == ["Rename B"])
    }

    /// Edit times move with every edit on any device; that alone touches no step.
    @Test mutating func aNewEditTimeAloneKeepsMapSteps() throws {
        try local.execute(RenameMapCommand(title: "Local"), named: "Rename Map")
        let stored = try remote { try $0.execute(rename("C", to: "Remote C")) }

        _ = try local.takeStored(stored, now: clock.now)

        #expect(local.undoStepNames == ["Rename Map"])
    }

    /// The safety net: a kept step that would break the graph clears history
    /// and changes nothing, instead of saving a broken map.
    @Test mutating func aKeptStepThatWouldBreakTheGraphClearsHistory() throws {
        try local.execute(rename("B", to: "Beta"), named: "Rename B")
        let stored = try remote { try $0.execute(rename("C", to: "Remote C")) }
        _ = try local.takeStored(stored, now: clock.now)
        local.history.retainUndoSteps { _ in true }
        var orphan = GraphChangeSet()
        var node = try #require(local.state.node(fixture["B"]))
        let before = node
        node.parentID = NodeID()
        // Undo applies `before`, so a step whose before has a missing parent breaks the tree.
        orphan.recordNode(node.id, before: node, after: before)
        local.history.record(orphan, named: "Broken")
        local.history.retainUndoSteps { _ in true }
        let state = local.state

        #expect(local.undo() == nil)
        #expect(local.state == state)
        #expect(!local.canUndo)
        #expect(!local.canRedo)
    }

    /// Repair of what arrives is deterministic and is not part of history.
    @Test mutating func twoEditorsTakingTheSameStoredMapAgree() throws {
        let stored = try remote { try $0.execute(DeleteNodeCommand(nodeID: fixture["A"])) }
        var other = try GraphEngine(state: fixture.state, clock: clock.ticking)

        _ = try local.takeStored(stored, now: clock.now)
        _ = try other.takeStored(stored, now: clock.now)

        #expect(local.state == other.state)
    }
}

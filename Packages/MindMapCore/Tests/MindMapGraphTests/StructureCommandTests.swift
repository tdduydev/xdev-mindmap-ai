import Foundation
import MindMapDomain
@testable import MindMapGraph
import Testing

@Suite("Undo and redo of structure commands")
struct StructureUndoRedoTests {
    static let base = """
    Root
      A
        A1
        A2
      B
        B1
      C
    """

    /// The fixture plus a link inside A's branch and one leaving it, so commands
    /// that touch links have some to work on.
    static func fixture() throws -> GraphFixture {
        var fixture = try GraphFixture(base)
        try fixture.engine.execute(ConnectNodesCommand(from: fixture["A1"], to: fixture["A2"]))
        try fixture.engine.execute(ConnectNodesCommand(from: fixture["B1"], to: fixture["A1"], type: .reference))
        try fixture.engine.execute(UpdateNodeCommand(nodeID: fixture["B"], .note("About B")))
        try fixture.engine.execute(UpdateNodeCommand(nodeID: fixture["C"], .title("C one\nC two")))
        return fixture
    }

    static func commands(for fixture: GraphFixture) -> [(String, any GraphCommand)] {
        let linkID = fixture.state.edges.values.first { $0.sourceNodeID == fixture["A1"] }!.id
        return [
            ("duplicate branch", DuplicateBranchCommand(nodeID: fixture["A"])),
            ("merge", MergeNodesCommand(into: fixture["A"], merging: [fixture["B"]])),
            ("split", SplitNodeCommand(nodeID: fixture["C"])),
            ("promote", PromoteNodeCommand(nodeID: fixture["A2"])),
            ("demote", DemoteNodeCommand(nodeID: fixture["B"])),
            ("connect", ConnectNodesCommand(from: fixture["C"], to: fixture["A"], label: "see")),
            ("remove link", RemoveEdgeCommand(edgeID: linkID)),
            ("collapse all", SetAllCollapsedCommand.collapseAll),
            ("expand all", SetAllCollapsedCommand.expandAll),
            ("rename map", RenameMapCommand(title: "Renamed")),
        ]
    }

    @Test func undoRestoresAndRedoReapplies() throws {
        var template = try Self.fixture()
        // Expand all needs something collapsed to expand.
        try template.engine.execute(UpdateNodeCommand(nodeID: template["B"], .isCollapsed(true)))
        for (name, command) in Self.commands(for: template) {
            var fixture = template
            let before = fixture.state

            let changes = try fixture.engine.execute(command)
            #expect(!changes.isEmpty, "\(name) changed something")
            let after = fixture.state

            fixture.engine.undo()
            #expect(sameContent(fixture.state, before), "undo of \(name)")
            fixture.engine.redo()
            #expect(sameContent(fixture.state, after), "redo of \(name)")
        }
    }
}

@Suite("Duplicating a branch")
struct DuplicateBranchCommandTests {
    @Test func copiesTheBranchRightAfterTheOriginal() throws {
        var fixture = try StructureUndoRedoTests.fixture()
        try fixture.engine.execute(UpdateNodeCommand(nodeID: fixture["A1"], .note("Detail")))
        let copyID = NodeID()

        try fixture.engine.execute(DuplicateBranchCommand(nodeID: fixture["A"], copyID: copyID))

        #expect(fixture.state.childIDs(of: fixture["Root"]) == [fixture["A"], copyID, fixture["B"], fixture["C"]])
        let copy = try #require(fixture.state.node(copyID))
        let copiedChildren = fixture.state.children(of: copyID)
        #expect(copy.parentID == fixture["Root"])
        #expect(copiedChildren.map(\.title) == ["A1", "A2"])
        #expect(copiedChildren.first?.note == "Detail")
        #expect(!copiedChildren.map(\.id).contains(fixture["A1"]))
    }

    @Test func copiesOnlyLinksInsideTheBranch() throws {
        var fixture = try StructureUndoRedoTests.fixture()
        let copyID = NodeID()

        try fixture.engine.execute(DuplicateBranchCommand(nodeID: fixture["A"], copyID: copyID))

        let copiedIDs = Set([copyID] + fixture.state.descendants(of: copyID))
        let copiedLinks = fixture.state.edges.values.filter {
            copiedIDs.contains($0.sourceNodeID) || copiedIDs.contains($0.targetNodeID)
        }
        #expect(fixture.state.edges.count == 3)
        #expect(copiedLinks.count == 1)
        let link = try #require(copiedLinks.first)
        #expect(fixture.state.node(link.sourceNodeID)?.title == "A1")
        #expect(fixture.state.node(link.targetNodeID)?.title == "A2")
    }

    @Test func keepsChildOrderEvenWithTiedSortKeys() throws {
        let map = MindMap(title: "Ties")
        let rootID = NodeID()
        let branchID = NodeID()
        let created = Date(timeIntervalSinceReferenceDate: 0)
        // Sync can leave siblings with the same sort order; creation time breaks the tie.
        let nodes = [
            MindNode(id: rootID, mapID: map.id, parentID: nil, title: "Root", createdAt: created),
            MindNode(id: branchID, mapID: map.id, parentID: rootID, title: "Branch", createdAt: created),
            MindNode(mapID: map.id, parentID: branchID, title: "first", createdAt: created),
            MindNode(mapID: map.id, parentID: branchID, title: "second", createdAt: created.addingTimeInterval(1)),
            MindNode(mapID: map.id, parentID: branchID, title: "third", createdAt: created.addingTimeInterval(2)),
        ]
        var withRoot = map
        withRoot.rootNodeID = rootID
        var engine = try GraphEngine(state: GraphState(map: withRoot, nodes: nodes, edges: []))
        let copyID = NodeID()

        try engine.execute(DuplicateBranchCommand(nodeID: branchID, copyID: copyID))

        #expect(engine.state.children(of: copyID).map(\.title) == ["first", "second", "third"])
    }

    @Test func theRootCannotBeDuplicated() throws {
        var fixture = try GraphFixture("Root")

        #expect(throws: GraphError.rootHasNoSiblings) {
            try fixture.engine.execute(DuplicateBranchCommand(nodeID: fixture["Root"]))
        }
    }
}

@Suite("Merging topics")
struct MergeNodesCommandTests {
    @Test func childrenMoveAndTheOthersAreDeleted() throws {
        var fixture = try GraphFixture("""
        Root
          A
            A1
          B
            B1
            B2
          C
            C1
        """)

        try fixture.engine.execute(MergeNodesCommand(into: fixture["A"], merging: [fixture["C"], fixture["B"]]))

        #expect(fixture.outline == """
        Root
          A
            A1
            C1
            B1
            B2
        """)
        #expect(fixture.state.node(fixture["B"]) == nil)
        #expect(fixture.state.node(fixture["C"]) == nil)
    }

    @Test func titlesAndNotesAreKeptInTheNote() throws {
        var fixture = try GraphFixture("""
        Root
          A
          B
          C
        """)
        try fixture.engine.execute(UpdateNodeCommand(nodeID: fixture["A"], .note("Why A")))
        try fixture.engine.execute(UpdateNodeCommand(nodeID: fixture["B"], .note("Why B")))

        try fixture.engine.execute(MergeNodesCommand(into: fixture["A"], merging: [fixture["B"], fixture["C"]]))

        let survivor = try #require(fixture.state.node(fixture["A"]))
        #expect(survivor.title == "A")
        #expect(survivor.note == "Why A\n\nB\nWhy B\n\nC")
    }

    @Test func linksMoveToTheSurvivor() throws {
        var fixture = try GraphFixture("""
        Root
          A
          B
          C
          D
        """)
        let toD = EdgeID()
        let duplicate = EdgeID()
        let between = EdgeID()
        try fixture.engine.execute(ConnectNodesCommand(edgeID: toD, from: fixture["B"], to: fixture["D"]))
        try fixture.engine.execute(ConnectNodesCommand(edgeID: duplicate, from: fixture["C"], to: fixture["D"]))
        try fixture.engine.execute(ConnectNodesCommand(edgeID: between, from: fixture["A"], to: fixture["B"]))

        try fixture.engine.execute(MergeNodesCommand(into: fixture["A"], merging: [fixture["B"], fixture["C"]]))

        // B→D becomes A→D; C→D would repeat it and A→B would point at itself.
        #expect(Set(fixture.state.edges.keys) == [toD])
        #expect(fixture.state.edges[toD]?.sourceNodeID == fixture["A"])
        #expect(GraphValidator.validate(fixture.state).isEmpty)
    }

    @Test func aCollapsedSurvivorOpensWhenItGainsChildren() throws {
        var fixture = try GraphFixture("""
        Root
          A
            A1
          B
            B1
        """)
        try fixture.engine.execute(UpdateNodeCommand(nodeID: fixture["A"], .isCollapsed(true)))

        try fixture.engine.execute(MergeNodesCommand(into: fixture["A"], merging: [fixture["B"]]))

        #expect(fixture.state.node(fixture["A"])?.isCollapsed == false)
    }

    @Test func onlySiblingsMerge() throws {
        var fixture = try GraphFixture("""
        Root
          A
            A1
          B
        """)
        let before = fixture.state

        #expect(throws: GraphError.notSiblings(fixture["A1"])) {
            try fixture.engine.execute(MergeNodesCommand(into: fixture["B"], merging: [fixture["A1"]]))
        }
        #expect(throws: GraphError.rootHasNoSiblings) {
            try fixture.engine.execute(MergeNodesCommand(into: fixture["Root"], merging: [fixture["A"]]))
        }
        #expect(fixture.state == before)
    }

    @Test func mergingNothingChangesNothing() throws {
        var fixture = try GraphFixture("""
        Root
          A
        """)

        let changes = try fixture.engine.execute(MergeNodesCommand(into: fixture["A"], merging: [fixture["A"]]))

        #expect(changes.isEmpty)
    }
}

@Suite("Splitting a topic")
struct SplitNodeCommandTests {
    @Test func eachLineBecomesASibling() throws {
        var fixture = try GraphFixture("""
        Root
          A
            A1
          B
        """)
        try fixture.engine.execute(UpdateNodeCommand(nodeID: fixture["A"], .title("One\n\n  Two \r\nThree")))
        try fixture.engine.execute(UpdateNodeCommand(nodeID: fixture["A"], .note("Kept")))

        try fixture.engine.execute(SplitNodeCommand(nodeID: fixture["A"]))

        #expect(fixture.outline == """
        Root
          One
            A1
          Two
          Three
          B
        """)
        // The original keeps its identity, so its children, note and links stay with the first line.
        #expect(fixture.state.node(fixture["A"])?.title == "One")
        #expect(fixture.state.node(fixture["A"])?.note == "Kept")
    }

    @Test func aSingleLineIsLeftAlone() throws {
        var fixture = try GraphFixture("""
        Root
          A
        """)

        let changes = try fixture.engine.execute(SplitNodeCommand(nodeID: fixture["A"]))

        #expect(changes.isEmpty)
    }

    @Test func theRootCannotSplit() throws {
        var fixture = try GraphFixture("Root")
        try fixture.engine.execute(UpdateNodeCommand(nodeID: fixture["Root"], .title("One\nTwo")))

        #expect(throws: GraphError.rootHasNoSiblings) {
            try fixture.engine.execute(SplitNodeCommand(nodeID: fixture["Root"]))
        }
    }
}

@Suite("Promoting and demoting")
struct PromoteDemoteCommandTests {
    static let base = """
    Root
      A
        A1
          A1a
        A2
      B
    """

    @Test func promoteMovesTheBranchRightAfterItsParent() throws {
        var fixture = try GraphFixture(Self.base)

        try fixture.engine.execute(PromoteNodeCommand(nodeID: fixture["A1"]))

        #expect(fixture.outline == """
        Root
          A
            A2
          A1
            A1a
          B
        """)
    }

    @Test func demoteMovesTheBranchUnderThePreviousSibling() throws {
        var fixture = try GraphFixture(Self.base)
        try fixture.engine.execute(UpdateNodeCommand(nodeID: fixture["A"], .isCollapsed(true)))

        try fixture.engine.execute(DemoteNodeCommand(nodeID: fixture["B"]))

        #expect(fixture.outline == """
        Root
          A
            A1
              A1a
            A2
            B
        """)
    }

    @Test func refusals() throws {
        var fixture = try GraphFixture(Self.base)
        let before = fixture.state

        #expect(throws: GraphError.cannotMoveRoot) {
            try fixture.engine.execute(PromoteNodeCommand(nodeID: fixture["Root"]))
        }
        #expect(throws: GraphError.alreadyTopLevel(fixture["A"])) {
            try fixture.engine.execute(PromoteNodeCommand(nodeID: fixture["A"]))
        }
        #expect(throws: GraphError.cannotMoveRoot) {
            try fixture.engine.execute(DemoteNodeCommand(nodeID: fixture["Root"]))
        }
        #expect(throws: GraphError.noPreviousSibling(fixture["A1"])) {
            try fixture.engine.execute(DemoteNodeCommand(nodeID: fixture["A1"]))
        }
        #expect(fixture.state == before)
    }

    @Test func availabilityMatchesTheRefusals() throws {
        let fixture = try GraphFixture(Self.base)
        let state = fixture.state

        #expect(!PromoteNodeCommand.canPromote(fixture["Root"], in: state))
        #expect(!PromoteNodeCommand.canPromote(fixture["A"], in: state))
        #expect(PromoteNodeCommand.canPromote(fixture["A1"], in: state))
        #expect(!DemoteNodeCommand.canDemote(fixture["Root"], in: state))
        #expect(!DemoteNodeCommand.canDemote(fixture["A"], in: state))
        #expect(DemoteNodeCommand.canDemote(fixture["A2"], in: state))
    }
}

@Suite("Cross-links")
struct LinkCommandTests {
    @Test func connectAndRemove() throws {
        var fixture = try GraphFixture("""
        Root
          A
          B
        """)
        let edgeID = EdgeID()

        try fixture.engine.execute(ConnectNodesCommand(edgeID: edgeID, from: fixture["A"], to: fixture["B"], type: .reference, label: "  cites "))

        let edge = try #require(fixture.state.edges[edgeID])
        #expect(edge.edgeType == .reference)
        #expect(edge.label == "cites")

        try fixture.engine.execute(RemoveEdgeCommand(edgeID: edgeID))
        #expect(fixture.state.edges.isEmpty)
        #expect(fixture.state.nodes.count == 3)
    }

    @Test func aBlankLabelIsNoLabel() throws {
        var fixture = try GraphFixture("""
        Root
          A
        """)
        let edgeID = EdgeID()

        try fixture.engine.execute(ConnectNodesCommand(edgeID: edgeID, from: fixture["Root"], to: fixture["A"], label: "  "))

        #expect(fixture.state.edges[edgeID]?.label == nil)
    }

    @Test func refusals() throws {
        var fixture = try GraphFixture("""
        Root
          A
        """)
        let edgeID = EdgeID()
        let ghost = NodeID()
        try fixture.engine.execute(ConnectNodesCommand(edgeID: edgeID, from: fixture["Root"], to: fixture["A"]))

        #expect(throws: GraphError.cannotLinkToItself(fixture["A"])) {
            try fixture.engine.execute(ConnectNodesCommand(from: fixture["A"], to: fixture["A"]))
        }
        #expect(throws: GraphError.nodeNotFound(ghost)) {
            try fixture.engine.execute(ConnectNodesCommand(from: fixture["A"], to: ghost))
        }
        #expect(throws: GraphError.edgeAlreadyExists(edgeID)) {
            try fixture.engine.execute(ConnectNodesCommand(from: fixture["Root"], to: fixture["A"]))
        }
        let missing = EdgeID()
        #expect(throws: GraphError.edgeNotFound(missing)) {
            try fixture.engine.execute(RemoveEdgeCommand(edgeID: missing))
        }
        // The other kind, or the other direction, is a different link.
        try fixture.engine.execute(ConnectNodesCommand(from: fixture["Root"], to: fixture["A"], type: .reference))
        try fixture.engine.execute(ConnectNodesCommand(from: fixture["A"], to: fixture["Root"]))
        #expect(fixture.state.edges.count == 3)
    }
}

@Suite("Collapse and expand all")
struct SetAllCollapsedCommandTests {
    static let base = """
    Root
      A
        A1
          A1a
      B
      C
        C1
    """

    @Test func collapseAllKeepsTheMainBranchesVisible() throws {
        var fixture = try GraphFixture(Self.base)
        try fixture.engine.execute(UpdateNodeCommand(nodeID: fixture["Root"], .isCollapsed(true)))

        let changes = try fixture.engine.execute(SetAllCollapsedCommand.collapseAll)

        #expect(fixture.outline == """
        Root
          A
          B
          C
        """)
        // Leaves are not touched.
        #expect(Set(changes.nodes.keys) == [fixture["Root"], fixture["A"], fixture["A1"], fixture["C"]])
    }

    @Test func expandAllShowsEverything() throws {
        var fixture = try GraphFixture(Self.base)
        try fixture.engine.execute(SetAllCollapsedCommand.collapseAll)

        try fixture.engine.execute(SetAllCollapsedCommand.expandAll)

        #expect(fixture.state.visibleOutline().count == fixture.state.nodes.count)
    }

    @Test func expandingAnExpandedMapIsANoOp() throws {
        var fixture = try GraphFixture(Self.base)

        let changes = try fixture.engine.execute(SetAllCollapsedCommand.expandAll)

        #expect(changes.isEmpty)
    }
}

@Suite("Renaming the map")
struct RenameMapCommandTests {
    @Test func renamesTheMapButNotTheCentralTopic() throws {
        var engine = try GraphEngine(state: GraphState.newMap(title: "Draft"))

        let changes = try engine.execute(RenameMapCommand(title: "Plan"))

        #expect(engine.state.map.title == "Plan")
        #expect(engine.state.root?.title == "Draft")
        #expect(changes.map?.before?.title == "Draft")
        #expect(changes.nodes.isEmpty)
    }
}

@Suite("Command cost")
struct CommandCostTests {
    /// NFR-PERF-02 sets 16 ms per command in a release build at 1,000 topics.
    /// Tests run in debug, which is slower, so this bound only catches a
    /// command that has gone quadratic; the real numbers go in the task note.
    /// A single timing against 100 ms failed when the Mac ran several builds at
    /// once (MM-88), so each command takes the median of a few runs, and every
    /// test run only fails ten times over the budget. The 100 ms budget is
    /// checked with MINDMAP_BENCHMARKS=1 on a quiet machine (docs/testing.md).
    @Test func structureCommandsStayFastAtAThousandTopics() throws {
        var engine = try GraphEngine(state: GraphState.newMap(title: "Large"))
        let rootID = try #require(engine.state.map.rootNodeID)
        var branches: [NodeID] = []
        for branch in 0..<20 {
            let id = NodeID()
            try engine.execute(AddNodeCommand(nodeID: id, .child(of: rootID), title: "Branch \(branch)"))
            branches.append(id)
        }
        for branch in branches {
            for leaf in 0..<49 {
                try engine.execute(AddNodeCommand(.child(of: branch), title: "Leaf \(leaf)"))
            }
        }
        #expect(engine.state.nodes.count == 1_001)

        let commands: [(String, any GraphCommand)] = [
            ("collapse all", SetAllCollapsedCommand.collapseAll),
            ("expand all", SetAllCollapsedCommand.expandAll),
            ("duplicate branch", DuplicateBranchCommand(nodeID: branches[0])),
            ("merge", MergeNodesCommand(into: branches[1], merging: [branches[2], branches[3]])),
            ("demote", DemoteNodeCommand(nodeID: branches[5])),
            ("promote", PromoteNodeCommand(nodeID: branches[5])),
        ]
        let budget = Duration.milliseconds(100)
        let limit = ProcessInfo.processInfo.environment["MINDMAP_BENCHMARKS"] == "1" ? budget : budget * 10
        let clock = ContinuousClock()
        for (name, command) in commands {
            // Each run starts from the same state: a command such as merge cannot
            // run twice on one engine.
            var times: [Duration] = []
            for _ in 0..<5 {
                var copy = engine
                times.append(try clock.measure { _ = try copy.execute(command) })
            }
            let median = times.sorted()[times.count / 2]
            print("\(name): median \(median) of \(times.count) runs (budget \(budget))")
            #expect(median < limit, "\(name) took \(median), median of \(times.count) runs")
            try engine.execute(command)
        }
    }
}

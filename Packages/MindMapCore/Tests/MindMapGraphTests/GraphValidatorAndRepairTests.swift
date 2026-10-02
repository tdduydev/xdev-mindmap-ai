import Foundation
import MindMapDomain
@testable import MindMapGraph
import Testing

/// Hand-built stored data, including the broken shapes sync can produce.
private struct StoredMap {
    let map: MindMap
    var nodes: [MindNode] = []
    var edges: [MindEdge] = []
    private var clock = Date(timeIntervalSinceReferenceDate: 800_000_000)

    init(rootID: NodeID?) {
        map = MindMap(title: "Stored", rootNodeID: rootID)
    }

    mutating func node(_ title: String, id: NodeID = NodeID(), parent: NodeID?) -> NodeID {
        clock = clock.addingTimeInterval(1)
        nodes.append(MindNode(id: id, mapID: map.id, parentID: parent, title: title, createdAt: clock))
        return id
    }

    var state: GraphState { GraphState(map: map, nodes: nodes, edges: edges) }
}

@Suite("Validation")
struct GraphValidatorTests {
    @Test func healthyGraphHasNoIssues() throws {
        let fixture = try GraphFixture("""
        Root
          A
            A1
          B
        """)

        #expect(GraphValidator.validate(fixture.state).isEmpty)
    }

    @Test func emptyMapIsValid() {
        #expect(GraphValidator.validate(GraphState(map: MindMap(title: "Empty"))).isEmpty)
    }

    @Test func findsAMissingRoot() {
        var stored = StoredMap(rootID: NodeID())
        _ = stored.node("Lonely", parent: nil)

        #expect(GraphValidator.validate(stored.state).contains(.missingRoot))
    }

    @Test func findsTheTopOfADetachedBranch() {
        let rootID = NodeID()
        var stored = StoredMap(rootID: rootID)
        _ = stored.node("Root", id: rootID, parent: nil)
        let top = stored.node("Orphan", parent: NodeID())
        _ = stored.node("Below orphan", parent: top)

        #expect(GraphValidator.validate(stored.state) == [.detachedBranch(top)])
    }

    @Test func findsAParentLoop() {
        let rootID = NodeID()
        var stored = StoredMap(rootID: rootID)
        _ = stored.node("Root", id: rootID, parent: nil)
        let a = NodeID()
        let b = NodeID()
        _ = stored.node("A", id: a, parent: b)
        _ = stored.node("B", id: b, parent: a)

        #expect(GraphValidator.validate(stored.state) == [.cycle(a), .cycle(b)])
    }

    @Test func findsBrokenEdges() {
        let rootID = NodeID()
        var stored = StoredMap(rootID: rootID)
        _ = stored.node("Root", id: rootID, parent: nil)
        let dangling = MindEdge(mapID: stored.map.id, sourceNodeID: rootID, targetNodeID: NodeID())
        let selfLoop = MindEdge(mapID: stored.map.id, sourceNodeID: rootID, targetNodeID: rootID)
        stored.edges = [dangling, selfLoop]

        #expect(GraphValidator.validate(stored.state) == [.danglingEdge(dangling.id), .selfLoopEdge(selfLoop.id)])
    }
}

@Suite("Repair")
struct GraphRepairTests {
    static let now = Date(timeIntervalSinceReferenceDate: 900_000_000)

    @Test func healthyGraphIsLeftAlone() throws {
        let fixture = try GraphFixture("""
        Root
          A
        """)

        let result = try GraphRepair.repair(fixture.state, now: Self.now)

        #expect(result.issues.isEmpty)
        #expect(result.changes.isEmpty)
        #expect(result.state == fixture.state)
    }

    @Test func detachedBranchIsHungUnderTheRoot() throws {
        let rootID = NodeID()
        var stored = StoredMap(rootID: rootID)
        _ = stored.node("Root", id: rootID, parent: nil)
        let top = stored.node("Orphan", parent: NodeID())
        let below = stored.node("Below orphan", parent: top)

        let result = try GraphRepair.repair(stored.state, now: Self.now)

        #expect(GraphValidator.validate(result.state).isEmpty)
        #expect(result.state.node(top)?.parentID == rootID)
        #expect(result.state.node(below)?.parentID == top)
        #expect(Set(result.changes.nodes.keys) == [top])
    }

    @Test func parentLoopIsCutAtTheMostRecentlyEditedNode() throws {
        let rootID = NodeID()
        var stored = StoredMap(rootID: rootID)
        _ = stored.node("Root", id: rootID, parent: nil)
        let a = NodeID()
        let b = NodeID()
        _ = stored.node("A", id: a, parent: b)
        _ = stored.node("B", id: b, parent: a)

        let result = try GraphRepair.repair(stored.state, now: Self.now)

        #expect(GraphValidator.validate(result.state).isEmpty)
        #expect(result.state.node(b)?.parentID == rootID)
        #expect(result.state.node(a)?.parentID == b)
    }

    @Test func missingRootIsReplacedByTheOldestParentlessNode() throws {
        var stored = StoredMap(rootID: NodeID())
        let first = stored.node("First", parent: nil)
        let second = stored.node("Second", parent: nil)
        let child = stored.node("Child of a deleted node", parent: NodeID())

        let result = try GraphRepair.repair(stored.state, now: Self.now)

        #expect(GraphValidator.validate(result.state).isEmpty)
        #expect(result.state.map.rootNodeID == first)
        #expect(result.state.node(second)?.parentID == first)
        #expect(result.state.node(child)?.parentID == first)
    }

    @Test func rootWithAParentIsCleared() throws {
        let rootID = NodeID()
        var stored = StoredMap(rootID: rootID)
        let child = NodeID()
        _ = stored.node("Root", id: rootID, parent: child)
        _ = stored.node("Child", id: child, parent: rootID)

        let result = try GraphRepair.repair(stored.state, now: Self.now)

        #expect(GraphValidator.validate(result.state).isEmpty)
        #expect(result.state.root?.parentID == nil)
        #expect(result.state.node(child)?.parentID == rootID)
    }

    @Test func brokenEdgesAreDroppedButNoNodeIsLost() throws {
        let rootID = NodeID()
        var stored = StoredMap(rootID: rootID)
        _ = stored.node("Root", id: rootID, parent: nil)
        _ = stored.node("Orphan", parent: NodeID())
        stored.edges = [MindEdge(mapID: stored.map.id, sourceNodeID: rootID, targetNodeID: NodeID())]

        let result = try GraphRepair.repair(stored.state, now: Self.now)

        #expect(result.state.edges.isEmpty)
        #expect(result.state.nodes.count == stored.nodes.count)
    }

    @Test func repairIsDeterministic() throws {
        var stored = StoredMap(rootID: nil)
        var previous: NodeID?
        for index in 0..<30 {
            // A tangle of loops and orphans with no root at all.
            let parent: NodeID? = index % 3 == 0 ? NodeID() : previous
            previous = stored.node("N\(index)", parent: parent)
        }
        let a = NodeID()
        let b = NodeID()
        _ = stored.node("Loop A", id: a, parent: b)
        _ = stored.node("Loop B", id: b, parent: a)

        let first = try GraphRepair.repair(stored.state, now: Self.now)
        let second = try GraphRepair.repair(stored.state, now: Self.now)

        #expect(first.state == second.state)
        #expect(GraphValidator.validate(first.state).isEmpty)
        #expect(first.state.nodes.count == stored.nodes.count)
        #expect(try GraphEngine(state: first.state).state == first.state)
    }

    @Test func duplicateRecordsKeepTheNewestCopy() {
        let rootID = NodeID()
        let map = MindMap(title: "Dupes", rootNodeID: rootID)
        let old = MindNode(id: rootID, mapID: map.id, parentID: nil, title: "Old", createdAt: Self.now)
        var new = old
        new.title = "New"
        new.updatedAt = Self.now.addingTimeInterval(10)

        let state = GraphState(map: map, nodes: [new, old], edges: [])

        #expect(state.root?.title == "New")
    }
}

@Suite("Traversal")
struct GraphTraversalTests {
    let fixture: GraphFixture

    init() throws {
        fixture = try GraphFixture("""
        Root
          A
            A1
              A1a
            A2
          B
        """)
    }

    @Test func ancestorsRunFromParentToRoot() {
        #expect(fixture.state.ancestors(of: fixture["A1a"]) == [fixture["A1"], fixture["A"], fixture["Root"]])
        #expect(fixture.state.ancestors(of: fixture["Root"]).isEmpty)
    }

    @Test func descendantsAreInReadingOrder() {
        #expect(fixture.state.descendants(of: fixture["A"]) == [fixture["A1"], fixture["A1a"], fixture["A2"]])
    }

    @Test func siblingsExcludeTheNodeItself() {
        #expect(fixture.state.siblings(of: fixture["A1"]) == [fixture["A2"]])
        #expect(fixture.state.siblings(of: fixture["Root"]).isEmpty)
    }

    @Test func depthCountsFromTheRoot() {
        #expect(fixture.state.depth(of: fixture["Root"]) == 0)
        #expect(fixture.state.depth(of: fixture["A1a"]) == 3)
        #expect(fixture.state.depth(of: NodeID()) == nil)
    }

    @Test func outlineSkipsInsideCollapsedBranches() throws {
        var fixture = fixture
        try fixture.engine.execute(UpdateNodeCommand(nodeID: fixture["A"], .isCollapsed(true)))

        #expect(fixture.outline == "Root\n  A\n  B")
        let a = try #require(fixture.state.visibleOutline().first { $0.nodeID == fixture["A"] })
        #expect(a.hasChildren)
    }
}

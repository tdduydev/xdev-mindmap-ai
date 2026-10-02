import CoreGraphics
import Foundation
import MindMapDomain
import MindMapGraph
@testable import MindMapLayout
import Testing

@Suite("Updating one branch")
struct IncrementalLayoutTests {
    let engine = HorizontalTreeLayout()
    let options = LayoutOptions()

    /// One edit the editor can make, with the topic whose measured size it changes.
    struct Edit: Sendable {
        let name: String
        let command: @Sendable (LayoutFixture, GraphState) -> any GraphCommand
        var resized: String?
    }

    static let edits: [Edit] = [
        Edit(name: "rename a leaf to a longer title", command: { f, _ in
            UpdateNodeCommand(nodeID: f["T150"], .title("A much longer title"))
        }, resized: "T150"),
        Edit(name: "rename the central topic", command: { f, _ in
            UpdateNodeCommand(nodeID: f["T0"], .title("Center"))
        }, resized: "T0"),
        Edit(name: "add a child deep down", command: { f, _ in
            AddNodeCommand(.child(of: f["T190"]), title: "New")
        }),
        Edit(name: "add a main branch", command: { f, _ in
            AddNodeCommand(.child(of: f["T0"], at: .first), title: "New")
        }),
        Edit(name: "collapse a branch", command: { f, _ in
            UpdateNodeCommand(nodeID: f["T3"], .isCollapsed(true))
        }),
        Edit(name: "delete a branch", command: { f, _ in
            DeleteNodeCommand(nodeID: f["T5"])
        }),
        Edit(name: "move a branch to another side", command: { f, state in
            // The last main branch sits on the left; move it under the first one, on the right.
            let mainBranches = state.childIDs(of: f["T0"])
            return ReparentNodeCommand(nodeID: mainBranches.last!, newParentID: mainBranches.first!)
        }),
        Edit(name: "move a topic to the front of its siblings", command: { f, state in
            let mainBranches = state.childIDs(of: f["T0"])
            return ReparentNodeCommand(nodeID: mainBranches.last!, newParentID: f["T0"], placement: .first)
        }),
    ]

    @Test(arguments: IncrementalLayoutTests.edits.indices)
    func updateMatchesAFullLayout(_ index: Int) throws {
        let edit = Self.edits[index]
        let fixture = LayoutFixture(randomTreeOf: 200, seed: 7)
        var graph = try fixture.engine()
        var sizes = variedSizes(for: graph.state, seed: 7)
        let before = engine.layout(graph.state, sizes: sizes, options: options)

        let changes = try graph.execute(edit.command(fixture, graph.state))
        var changed = changes.layoutInvalidation
        if let resized = edit.resized {
            sizes[fixture[resized]] = CGSize(width: 333, height: 77)
            changed.insert(fixture[resized])
        }
        let updated = engine.update(before, graph: graph.state, sizes: sizes, options: options, changed: changed)
        #expect(updated == engine.layout(graph.state, sizes: sizes, options: options), "\(edit.name)")

        // Undo and redo are edits too, and must land on the same geometry.
        // #require cannot wrap a mutating call, so take the result first.
        let undoResult = graph.undo()
        let undone = try #require(undoResult)
        let afterUndo = engine.update(updated, graph: graph.state, sizes: sizes, options: options, changed: undone.layoutInvalidation)
        #expect(afterUndo == engine.layout(graph.state, sizes: sizes, options: options), "undo \(edit.name)")
        let redoResult = graph.redo()
        let redone = try #require(redoResult)
        let afterRedo = engine.update(afterUndo, graph: graph.state, sizes: sizes, options: options, changed: redone.layoutInvalidation)
        #expect(afterRedo == updated, "redo \(edit.name)")
    }

    /// Chained updates, each built on the last, so stale entries cannot pile up.
    /// New topics get IDs from a counter, so a failing step replays the same way.
    @Test(arguments: BranchSides.allCases, [UInt64(11), 12, 13])
    func chainedUpdatesStayEqualToFullLayouts(_ sides: BranchSides, seed: UInt64) throws {
        let options = LayoutOptions(sides: sides)
        let fixture = LayoutFixture(randomTreeOf: 150, seed: 3)
        var graph = try fixture.engine()
        var sizes = variedSizes(for: graph.state, seed: 3)
        var layout = engine.layout(graph.state, sizes: sizes, options: options)
        var random = SplitMix64(seed: seed)

        for step in 0..<60 {
            let ids = graph.state.nodes.keys.sorted()
            let target = ids[random.nextInt(below: ids.count)]
            let other = ids[random.nextInt(below: ids.count)]
            let newID = NodeID(UUID(uuidString: String(format: "00000000-0000-0000-0001-%012X", step))!)
            let changed: Set<NodeID>
            switch random.nextInt(below: 8) {
            case 5:
                guard let changes = graph.undo() else { continue }
                changed = changes.layoutInvalidation
            case 6:
                guard let changes = graph.redo() else { continue }
                changed = changes.layoutInvalidation
            case 7:
                // A title that wraps differently, or a Dynamic Type change: no command.
                sizes[target] = CGSize(width: CGFloat(50 + random.nextInt(below: 300)), height: CGFloat(20 + random.nextInt(below: 100)))
                changed = [target]
            case let kind:
                // Deleting the root empties the map, which ends the chain; skip it.
                if kind == 3, target == graph.state.map.rootNodeID { continue }
                let command: any GraphCommand = switch kind {
                case 0: AddNodeCommand(nodeID: newID, .child(of: target), title: "S\(step)")
                case 1: UpdateNodeCommand(nodeID: target, .isCollapsed(!(graph.state.node(target)?.isCollapsed ?? false)))
                case 2: ReparentNodeCommand(nodeID: target, newParentID: other)
                case 3: DeleteNodeCommand(nodeID: target)
                default: AddNodeCommand(nodeID: newID, .sibling(after: target), title: "S\(step)")
                }
                // Moves into a topic's own branch, and siblings of the root, are refused; skip those.
                guard let changes = try? graph.execute(command) else { continue }
                changed = changes.layoutInvalidation
            }
            layout = engine.update(layout, graph: graph.state, sizes: sizes, options: options, changed: changed)
            #expect(layout == engine.layout(graph.state, sizes: sizes, options: options), "step \(step)")
        }
    }

    /// A move from the branch below into the one above keeps the block's top in
    /// place: the receiving topic is re-centered lower, while its first child,
    /// untouched, keeps its frame. The child's connector must still follow the parent.
    @Test func untouchedChildFollowsItsMovedParent() throws {
        let fixture = LayoutFixture("""
        Root
          P
            P1
            P2
          Q
            Q1
            Q2
            Q3
        """)
        let options = LayoutOptions(sides: .rightOnly)
        var graph = try fixture.engine()
        let before = engine.layout(graph.state, sizes: [:], options: options)

        let changes = try graph.execute(ReparentNodeCommand(nodeID: fixture["Q3"], newParentID: fixture["P"]))
        let updated = engine.update(before, graph: graph.state, sizes: [:], options: options, changed: changes.layoutInvalidation)
        let full = engine.layout(graph.state, sizes: [:], options: options)

        // The situation the test is about: P moved, P1 did not.
        #expect(full.frame(fixture["P"]) != before.frame(fixture["P"]))
        #expect(full.frame(fixture["P1"]) == before.frame(fixture["P1"]))
        #expect(updated.connectors[fixture["P1"]]?.start.y == full.frame(fixture["P"]).midY)
        #expect(updated == full)
    }

    @Test func crossLinkEditsShowWithoutAnyChangedTopic() {
        var fixture = LayoutFixture("Root\n  A\n  B")
        let before = engine.layout(fixture.state, sizes: [:], options: options)
        fixture.link("A", "B")
        let updated = engine.update(before, graph: fixture.state, sizes: [:], options: options, changed: [])
        #expect(updated.crossLinks.count == 1)
        #expect(updated == engine.layout(fixture.state, sizes: [:], options: options))
    }

    @Test func changedOptionsLayOutEverythingAgain() {
        let fixture = LayoutFixture("Root\n  A\n  B")
        let before = engine.layout(fixture.state, sizes: [:], options: options)
        let rightOnly = LayoutOptions(sides: .rightOnly)
        let updated = engine.update(before, graph: fixture.state, sizes: [:], options: rightOnly, changed: [])
        #expect(updated == engine.layout(fixture.state, sizes: [:], options: rightOnly))
        #expect(updated.nodes[fixture["B"]]?.side == .right)
    }

    @Test func onlyTheChangedPathIsMeasuredAgain() {
        let fixture = LayoutFixture("""
        Root
          A
            A1
              A11
          B
            B1
        """)
        let dirty = HorizontalTreeLayout.dirtyBranches(for: [fixture["A11"]], in: fixture.state)
        #expect(dirty == [fixture["A11"], fixture["A1"], fixture["A"], fixture["Root"]])
    }

    @Test func layoutInvalidationNamesBothParentsOfAMove() throws {
        let fixture = LayoutFixture("Root\n  A\n    A1\n  B")
        var graph = try fixture.engine()
        let changes = try graph.execute(ReparentNodeCommand(nodeID: fixture["A1"], newParentID: fixture["B"]))
        #expect(changes.layoutInvalidation.isSuperset(of: [fixture["A1"], fixture["A"], fixture["B"]]))
    }
}

@Suite("Layout performance")
struct LayoutPerformanceTests {
    let engine = HorizontalTreeLayout()
    let options = LayoutOptions()

    /// NFR-PERF-06 targets 1,000 topics under 50 ms on a Mac M1, and one branch
    /// faster than the whole map. The numbers are printed, not asserted: timings
    /// on a shared or busy machine, in a debug build, would make the suite flaky.
    /// Medians of several runs keep one slow run from skewing what is printed.
    @Test func thousandTopics() throws {
        let fixture = LayoutFixture(randomTreeOf: 1_000, seed: 2026)
        var graph = try fixture.engine()
        var sizes = variedSizes(for: graph.state, seed: 2026)

        var full: MapLayout?
        let fullTime = median(of: 15) {
            full = engine.layout(graph.state, sizes: sizes, options: options)
        }
        let previous = try #require(full)
        #expect(previous.nodes.count == 1_000)

        let leaf = try #require(graph.state.nodes.keys.sorted().first { graph.state.childIDs(of: $0).isEmpty })
        let changes = try graph.execute(UpdateNodeCommand(nodeID: leaf, .title("Renamed")))
        sizes[leaf] = CGSize(width: 240, height: 64)
        let changed = changes.layoutInvalidation.union([leaf])
        var updated: MapLayout?
        let updateTime = median(of: 15) {
            updated = engine.update(previous, graph: graph.state, sizes: sizes, options: options, changed: changed)
        }
        #expect(updated == engine.layout(graph.state, sizes: sizes, options: options))

        let target = Duration.milliseconds(50)
        print("""
        Layout of 1,000 topics (median of 15): full \(milliseconds(fullTime)) ms, \
        one-branch update \(milliseconds(updateTime)) ms; \
        target full < \(milliseconds(target)) ms on a Mac M1 (\(fullTime < target ? "met" : "not met") here)
        """)
    }

    private func milliseconds(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        let value = Double(seconds) * 1_000 + Double(attoseconds) / 1e15
        // A fixed format, so logs read the same whatever the machine's locale.
        return String(format: "%.2f", value)
    }

    private func median(of runs: Int, _ body: () -> Void) -> Duration {
        let clock = ContinuousClock()
        var times: [Duration] = []
        for _ in 0..<runs {
            times.append(clock.measure(body))
        }
        return times.sorted()[runs / 2]
    }
}

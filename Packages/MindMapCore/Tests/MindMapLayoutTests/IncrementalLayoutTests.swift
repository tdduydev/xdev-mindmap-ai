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
        let undone = try #require(graph.undo())
        let afterUndo = engine.update(updated, graph: graph.state, sizes: sizes, options: options, changed: undone.layoutInvalidation)
        #expect(afterUndo == engine.layout(graph.state, sizes: sizes, options: options), "undo \(edit.name)")
        let redone = try #require(graph.redo())
        let afterRedo = engine.update(afterUndo, graph: graph.state, sizes: sizes, options: options, changed: redone.layoutInvalidation)
        #expect(afterRedo == updated, "redo \(edit.name)")
    }

    /// Chained updates, each built on the last, so stale entries cannot pile up.
    @Test func chainedUpdatesStayEqualToFullLayouts() throws {
        let fixture = LayoutFixture(randomTreeOf: 150, seed: 3)
        var graph = try fixture.engine()
        let sizes = variedSizes(for: graph.state, seed: 3)
        var layout = engine.layout(graph.state, sizes: sizes, options: options)
        var random = SplitMix64(seed: 11)

        for step in 0..<60 {
            let ids = graph.state.nodes.keys.sorted()
            let target = ids[random.nextInt(below: ids.count)]
            let other = ids[random.nextInt(below: ids.count)]
            let command: any GraphCommand = switch random.nextInt(below: 5) {
            case 0: AddNodeCommand(.child(of: target), title: "S\(step)")
            case 1: UpdateNodeCommand(nodeID: target, .isCollapsed(!(graph.state.node(target)?.isCollapsed ?? false)))
            case 2: ReparentNodeCommand(nodeID: target, newParentID: other)
            case 3: DeleteNodeCommand(nodeID: target)
            default: AddNodeCommand(.sibling(after: target), title: "S\(step)")
            }
            // Moves into a topic's own branch, or deleting the root, are refused; skip those.
            guard let changes = try? graph.execute(command) else { continue }
            layout = engine.update(layout, graph: graph.state, sizes: sizes, options: options, changed: changes.layoutInvalidation)
            #expect(layout == engine.layout(graph.state, sizes: sizes, options: options), "step \(step)")
        }
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

    /// NFR-PERF-06: 1,000 topics under 50 ms, and one branch faster than the whole map.
    /// Medians of several runs keep a busy machine from failing the test.
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

        print("Layout of 1,000 topics: full \(fullTime), one branch \(updateTime)")
        #expect(fullTime < .milliseconds(50))
        #expect(updateTime < fullTime)
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

import CoreGraphics
import Foundation
import MindMapDomain
import MindMapGraph
@testable import MindMapLayout
import Testing

@Suite("Horizontal tree layout")
struct HorizontalTreeLayoutTests {
    let engine = HorizontalTreeLayout()
    let options = LayoutOptions()

    @Test func emptyMapHasNoGeometry() {
        let state = GraphState(map: MindMap(title: "Empty"))
        let layout = engine.layout(state, sizes: [:], options: options)
        #expect(layout.nodes.isEmpty)
        #expect(layout.bounds == .zero)
        #expect(layout.rootID == nil)
    }

    @Test func singleTopicIsCenteredOnTheOrigin() throws {
        let fixture = LayoutFixture("Root")
        let layout = engine.layout(fixture.state, sizes: [fixture["Root"]: CGSize(width: 100, height: 40)], options: options)

        let root = try #require(layout.nodes[fixture["Root"]])
        #expect(root.frame == CGRect(x: -50, y: -20, width: 100, height: 40))
        #expect(root.side == .center)
        #expect(root.depth == 0)
        #expect(layout.connectors.isEmpty)
        #expect(layout.bounds == root.frame)
    }

    @Test func missingSizesFallBackToTheDefault() {
        let fixture = LayoutFixture("Root\n  A")
        let layout = engine.layout(fixture.state, sizes: [:], options: options)
        #expect(layout.frame(fixture["A"]).size == options.defaultNodeSize)
    }

    @Test func childrenStartOneGapPastTheirParentOnEachSide() throws {
        let fixture = LayoutFixture("""
        Root
          R
            R1
          L
            L1
        """)
        let layout = engine.layout(fixture.state, sizes: [:], options: options)
        let gap = options.horizontalSpacing

        #expect(layout.nodes[fixture["R"]]?.side == .right)
        #expect(layout.nodes[fixture["L"]]?.side == .left)
        #expect(layout.frame(fixture["R"]).minX == layout.frame(fixture["Root"]).maxX + gap)
        #expect(layout.frame(fixture["R1"]).minX == layout.frame(fixture["R"]).maxX + gap)
        #expect(layout.frame(fixture["L"]).maxX == layout.frame(fixture["Root"]).minX - gap)
        #expect(layout.frame(fixture["L1"]).maxX == layout.frame(fixture["L"]).minX - gap)

        let connector = try #require(layout.connectors[fixture["R1"]])
        #expect(connector.start == CGPoint(x: layout.frame(fixture["R"]).maxX, y: layout.frame(fixture["R"]).midY))
        #expect(connector.end == CGPoint(x: layout.frame(fixture["R1"]).minX, y: layout.frame(fixture["R1"]).midY))
        let leftConnector = try #require(layout.connectors[fixture["L1"]])
        #expect(leftConnector.start.x == layout.frame(fixture["L"]).minX)
        #expect(leftConnector.end.x == layout.frame(fixture["L1"]).maxX)
    }

    @Test func deepChainGrowsOutwardWithoutOverflowingTheStack() throws {
        var fixture = LayoutFixture("Root")
        var parent = fixture["Root"]
        for level in 1...3_000 {
            parent = fixture.add("N\(level)", parent: parent)
        }
        let layout = engine.layout(fixture.state, sizes: [:], options: options)

        #expect(layout.nodes.count == 3_001)
        let last = try #require(layout.nodes[fixture["N3000"]])
        #expect(last.depth == 3_000)
        #expect(last.side == .right)
        // A single chain has one topic per band, so it stays on the root's line.
        #expect(last.frame.midY == 0)
        #expect(layout.frame(fixture["N2"]).minX > layout.frame(fixture["N1"]).maxX)
    }

    @Test func wideTreeStacksSiblingsWithoutOverlap() {
        var fixture = LayoutFixture("Root")
        for index in 0..<40 {
            fixture.add("C\(index)", parent: fixture["Root"])
        }
        let layout = engine.layout(fixture.state, sizes: [:], options: options)

        #expect(layout.overlappingPairs.isEmpty)
        // Equal weights split evenly: the first half right, the rest left.
        #expect((0..<20).allSatisfy { layout.nodes[fixture["C\($0)"]]?.side == .right })
        #expect((20..<40).allSatisfy { layout.nodes[fixture["C\($0)"]]?.side == .left })
        let gap = layout.frame(fixture["C1"]).minY - layout.frame(fixture["C0"]).maxY
        #expect(gap == options.verticalSpacing)
        // Each side is centered on the central topic.
        #expect(layout.frame(fixture["C0"]).minY == -layout.frame(fixture["C19"]).maxY)
    }

    @Test func balancedSidesFollowTopicCountsAndReadClockwise() {
        let fixture = LayoutFixture("""
        Root
          A
            A1
            A2
            A3
          B
          C
          D
        """)
        let layout = engine.layout(fixture.state, sizes: [:], options: options)

        // A holds 4 of the 7 topics below the root, so it is alone on the right.
        #expect(layout.nodes[fixture["A"]]?.side == .right)
        for title in ["B", "C", "D"] {
            #expect(layout.nodes[fixture[title]]?.side == .left)
        }
        // Down the right, then up the left: B, the first left branch, is lowest.
        #expect(layout.frame(fixture["D"]).maxY < layout.frame(fixture["C"]).minY)
        #expect(layout.frame(fixture["C"]).maxY < layout.frame(fixture["B"]).minY)
    }

    @Test func oddBranchCountPutsTheExtraOnTheRight() {
        let fixture = LayoutFixture("Root\n  A\n  B\n  C")
        let layout = engine.layout(fixture.state, sizes: [:], options: options)
        #expect(layout.nodes[fixture["A"]]?.side == .right)
        #expect(layout.nodes[fixture["B"]]?.side == .right)
        #expect(layout.nodes[fixture["C"]]?.side == .left)
    }

    @Test(arguments: [BranchSides.rightOnly, .leftOnly])
    func oneSidedLayoutsKeepEveryBranchOnOneSide(_ sides: BranchSides) {
        let fixture = LayoutFixture("Root\n  A\n    A1\n  B\n  C")
        let layout = engine.layout(fixture.state, sizes: [:], options: LayoutOptions(sides: sides))
        let expected: LayoutSide = sides == .rightOnly ? .right : .left
        for title in ["A", "A1", "B", "C"] {
            #expect(layout.nodes[fixture[title]]?.side == expected)
        }
        #expect(layout.overlappingPairs.isEmpty)
        // Display order reads top to bottom on a single side, left as well as right.
        #expect(layout.frame(fixture["A"]).maxY < layout.frame(fixture["B"]).minY)
        #expect(layout.frame(fixture["B"]).maxY < layout.frame(fixture["C"]).minY)
    }

    @Test func collapsedBranchTakesNoSpace() {
        let expanded = LayoutFixture("""
        Root
          A
            A1
            A2
              A21
          B
        """)
        var collapsed = expanded
        collapsed.collapse("A")
        let bare = LayoutFixture("Root\n  A\n  B")

        let layout = engine.layout(collapsed.state, sizes: [:], options: options)
        #expect(layout.nodes[collapsed["A1"]] == nil)
        #expect(layout.nodes[collapsed["A21"]] == nil)
        #expect(layout.connectors[collapsed["A1"]] == nil)
        #expect(layout.nodes[collapsed["A"]]?.hiddenDescendantCount == 3)
        #expect(layout.nodes[collapsed["B"]]?.hiddenDescendantCount == 0)

        // Laid out exactly like the same map without A's children.
        let bareLayout = engine.layout(bare.state, sizes: [:], options: options)
        #expect(layout.frame(collapsed["A"]) == bareLayout.frame(bare["A"]))
        #expect(layout.frame(collapsed["B"]) == bareLayout.frame(bare["B"]))
        #expect(layout.bounds == bareLayout.bounds)

        let expandedLayout = engine.layout(expanded.state, sizes: [:], options: options)
        #expect(expandedLayout.bounds.height > layout.bounds.height || expandedLayout.bounds.width > layout.bounds.width)
    }

    @Test func topicsOfDifferentSizesNeverOverlap() {
        for seed in UInt64(1)...5 {
            let fixture = LayoutFixture(randomTreeOf: 250, seed: seed)
            let state = fixture.state
            let layout = engine.layout(state, sizes: variedSizes(for: state, seed: seed), options: options)
            #expect(layout.nodes.count == 250)
            #expect(layout.overlappingPairs.isEmpty, "seed \(seed)")
        }
    }

    @Test func boundsHoldEveryTopic() {
        let fixture = LayoutFixture(randomTreeOf: 120, seed: 9)
        let state = fixture.state
        let layout = engine.layout(state, sizes: variedSizes(for: state, seed: 9), options: options)
        #expect(layout.nodes.values.allSatisfy { layout.bounds.contains($0.frame) })
        #expect(layout.nodes.values.contains { $0.frame.minX == layout.bounds.minX })
        #expect(layout.nodes.values.contains { $0.frame.maxY == layout.bounds.maxY })
    }

    @Test func sameInputGivesTheSameLayout() {
        let fixture = LayoutFixture(randomTreeOf: 300, seed: 42)
        let state = fixture.state
        let sizes = variedSizes(for: state, seed: 42)
        // Node order in storage, as sync might deliver it, must not matter.
        let shuffled = GraphState(map: state.map, nodes: fixture.nodes.reversed(), edges: [])

        let first = engine.layout(state, sizes: sizes, options: options)
        #expect(engine.layout(state, sizes: sizes, options: options) == first)
        #expect(engine.layout(shuffled, sizes: sizes, options: options) == first)
    }

    @Test func crossLinksJoinVisibleTopicsOnly() throws {
        var fixture = LayoutFixture("""
        Root
          A
            A1
          B
        """)
        fixture.link("A", "B")
        fixture.link("A1", "B")
        fixture.collapse("A")
        let layout = engine.layout(fixture.state, sizes: [:], options: options)

        #expect(layout.crossLinks.count == 1)
        let path = try #require(layout.crossLinks[fixture.edges[0].id])
        let a = layout.frame(fixture["A"])
        let b = layout.frame(fixture["B"])
        // A is on the right and B on the left, so the link leaves A's left edge.
        #expect(path.start == CGPoint(x: a.minX, y: a.midY))
        #expect(path.end == CGPoint(x: b.maxX, y: b.midY))
    }

    @Test func styleNamesItsEngine() {
        #expect(LayoutStyle.horizontalTree.engine is HorizontalTreeLayout)
    }
}

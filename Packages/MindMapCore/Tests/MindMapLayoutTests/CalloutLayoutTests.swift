import CoreGraphics
import Foundation
import MindMapDomain
import MindMapGraph
@testable import MindMapLayout
import Testing

@Suite("Callouts in the layout")
struct CalloutLayoutTests {
    let engine = HorizontalTreeLayout()
    let options = LayoutOptions()
    static let bubble = CGSize(width: 100, height: 30)

    static func fixture() -> LayoutFixture {
        var fixture = LayoutFixture("""
        Root
          A
            A1
            A2
          B
          C
        """)
        fixture.setCallout("B", "Check the budget")
        return fixture
    }

    @Test func bubbleSitsAboveTheCardWithTheSpacing() throws {
        let fixture = Self.fixture()
        let layout = engine.layout(fixture.state, sizes: [:], callouts: [fixture["B"]: Self.bubble], options: options)
        let node = try #require(layout.nodes[fixture["B"]])
        let bubble = try #require(node.calloutFrame)

        #expect(bubble.size == Self.bubble)
        #expect(bubble.maxY == node.frame.minY - options.calloutSpacing)
        // Narrower than the card: centred on it.
        #expect(bubble.midX == node.frame.midX)
        #expect(layout.nodes[fixture["A"]]?.calloutFrame == nil)
        #expect(layout.bounds.contains(bubble))
    }

    /// The room is reserved: the sibling above moves up by the bubble and its
    /// spacing, and the connector still ends on the card's centre.
    @Test func siblingAboveMakesRoomAndConnectorEndsOnTheCard() throws {
        let fixture = Self.fixture()
        // Everything on the right, so A's branch is the band right above B.
        let options = LayoutOptions(sides: .rightOnly)
        let plain = engine.layout(fixture.state, sizes: [:], callouts: [:], options: options)
        let layout = engine.layout(fixture.state, sizes: [:], callouts: [fixture["B"]: Self.bubble], options: options)

        let card = layout.frame(fixture["B"])
        let bubble = try #require(layout.nodes[fixture["B"]]?.calloutFrame)
        let above = layout.frame(fixture["A2"])
        #expect(above.maxY + options.verticalSpacing <= bubble.minY)
        #expect(layout.connectors[fixture["B"]]?.end == CGPoint(x: card.minX, y: card.midY))
        #expect(layout.overlappingCardsAndCallouts.isEmpty)
        // Without a callout size the topic takes no extra room.
        #expect(plain.nodes.values.allSatisfy { $0.calloutFrame == nil })
    }

    /// A bubble wider than its card stays on the card's parent-facing edge and
    /// pushes the children past its far edge.
    @Test func wideBubbleKeepsOutOfTheParentAndChildrenColumns() throws {
        var fixture = Self.fixture()
        fixture.setCallout("A", "A long remark that is wider than the card")
        fixture.add("L1", parent: fixture["Root"])
        fixture.add("L2", parent: fixture["Root"])
        fixture.add("L3", parent: fixture["Root"])
        fixture.add("L3a", parent: fixture["L3"])
        fixture.setCallout("L3", "Left side remark that is wide")
        let wide = CGSize(width: 300, height: 44)
        let layout = engine.layout(
            fixture.state,
            sizes: [:],
            callouts: [fixture["A"]: wide, fixture["L3"]: wide],
            options: options
        )

        let a = try #require(layout.nodes[fixture["A"]])
        let aBubble = try #require(a.calloutFrame)
        #expect(a.side == .right)
        #expect(aBubble.minX == a.frame.minX)
        #expect(layout.frame(fixture["A1"]).minX == aBubble.maxX + options.horizontalSpacing)

        let l3 = try #require(layout.nodes[fixture["L3"]])
        let l3Bubble = try #require(l3.calloutFrame)
        #expect(l3.side == .left)
        #expect(l3Bubble.maxX == l3.frame.maxX)
        #expect(layout.frame(fixture["L3a"]).maxX == l3Bubble.minX - options.horizontalSpacing)
        #expect(layout.overlappingCardsAndCallouts.isEmpty)
    }

    @Test func centralAndFloatingTopicsCarryABubble() throws {
        var fixture = Self.fixture()
        fixture.setCallout("Root", "Draft")
        fixture.addFloating("Idea", at: TopicPosition(x: 600, y: 400))
        fixture.add("I1", parent: fixture["Idea"])
        fixture.setCallout("Idea", "Aside")
        let wide = CGSize(width: 260, height: 30)
        let layout = engine.layout(
            fixture.state,
            sizes: [:],
            callouts: [fixture["Root"]: wide, fixture["Idea"]: wide],
            options: options
        )
        let root = try #require(layout.nodes[fixture["Root"]])
        let rootBubble = try #require(root.calloutFrame)
        #expect(rootBubble.midX == root.frame.midX)
        #expect(layout.frame(fixture["A"]).minX == rootBubble.maxX + options.horizontalSpacing)

        let idea = try #require(layout.nodes[fixture["Idea"]])
        #expect(idea.frame.midX == 600 && idea.frame.midY == 400)
        #expect(idea.calloutFrame?.maxY == idea.frame.minY - options.calloutSpacing)
    }

    /// A size passed for a topic whose callout is gone is ignored.
    @Test func sizeWithoutCalloutTextIsIgnored() {
        let fixture = Self.fixture()
        let layout = engine.layout(fixture.state, sizes: [:], callouts: [fixture["A"]: Self.bubble], options: options)
        #expect(layout.nodes[fixture["A"]]?.calloutFrame == nil)
        #expect(layout == engine.layout(fixture.state, sizes: [:], callouts: [:], options: options))
    }

    @Test(arguments: BranchSides.allCases, [UInt64(3), 4, 5])
    func randomMapsWithCalloutsNeverOverlapAndAreDeterministic(_ sides: BranchSides, seed: UInt64) {
        var fixture = LayoutFixture(randomTreeOf: 150, seed: seed)
        var random = SplitMix64(seed: seed &+ 100)
        var callouts: [NodeID: CGSize] = [:]
        for index in 0..<150 where random.nextInt(below: 4) == 0 {
            fixture.setCallout("T\(index)", "Remark \(index)")
            let width = CGFloat(40 + random.nextInt(below: 320))
            callouts[fixture["T\(index)"]] = CGSize(width: width, height: CGFloat(24 + 18 * random.nextInt(below: 3)))
        }
        let options = LayoutOptions(sides: sides)
        let sizes = variedSizes(for: fixture.state, seed: seed)
        let layout = engine.layout(fixture.state, sizes: sizes, callouts: callouts, options: options)

        #expect(layout.overlappingCardsAndCallouts.isEmpty)
        #expect(layout.nodes.values.filter { $0.calloutFrame != nil }.count == callouts.count)
        #expect(layout == engine.layout(fixture.state, sizes: sizes, callouts: callouts, options: options))
    }

    /// Adding, editing and removing a callout through commands, then undo and
    /// redo: each incremental update equals a full layout.
    @Test func updatesAfterCalloutCommandsMatchAFullLayout() throws {
        let fixture = LayoutFixture(randomTreeOf: 120, seed: 9)
        var graph = try fixture.engine()
        let sizes = variedSizes(for: graph.state, seed: 9)
        let target = fixture["T17"]
        var callouts: [NodeID: CGSize] = [:]
        var layout = engine.layout(graph.state, sizes: sizes, callouts: callouts, options: options)

        func step(_ changes: GraphChangeSet, bubble: CGSize?, _ name: String) {
            callouts[target] = bubble
            layout = engine.update(
                layout, graph: graph.state, sizes: sizes, callouts: callouts, options: options,
                changed: changes.layoutInvalidation
            )
            #expect(layout == engine.layout(graph.state, sizes: sizes, callouts: callouts, options: options), "\(name)")
        }

        step(try graph.execute(SetCalloutCommand(nodeIDs: [target], text: "Short")), bubble: CGSize(width: 60, height: 24), "add")
        step(try graph.execute(SetCalloutCommand(nodeIDs: [target], text: "A much longer remark")), bubble: CGSize(width: 280, height: 60), "edit")
        step(try graph.execute(SetCalloutCommand(nodeIDs: [target], text: nil)), bubble: nil, "remove")
        let undoResult = graph.undo()
        let undone = try #require(undoResult)
        step(undone, bubble: CGSize(width: 280, height: 60), "undo")
        let redoResult = graph.redo()
        let redone = try #require(redoResult)
        step(redone, bubble: nil, "redo")
    }
}

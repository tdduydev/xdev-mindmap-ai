import CoreGraphics
import Foundation
import MindMapDomain
import MindMapGraph
@testable import MindMapLayout
import Testing

@Suite("Floating topics in the layout")
struct FloatingLayoutTests {
    let engine = HorizontalTreeLayout()
    let options = LayoutOptions()

    static func fixture() -> LayoutFixture {
        var fixture = LayoutFixture("""
        Root
          A
          B
        """)
        let idea = fixture.addFloating("Idea", at: TopicPosition(x: 400, y: -300))
        fixture.add("I1", parent: idea)
        fixture.add("I2", parent: idea)
        fixture.addFloating("Aside", at: TopicPosition(x: -350.5, y: 260))
        return fixture
    }

    @Test func floatingTopicIsCentredOnItsPosition() throws {
        let fixture = Self.fixture()
        let size = CGSize(width: 140, height: 40)
        let layout = engine.layout(fixture.state, sizes: [fixture["Idea"]: size], options: options)

        let idea = try #require(layout.nodes[fixture["Idea"]])
        #expect(idea.frame == CGRect(x: 400 - 70, y: -300 - 20, width: 140, height: 40))
        #expect(idea.side == .right)
        #expect(idea.depth == 1)
        #expect(layout.connectors[fixture["Idea"]] == nil)
        #expect(layout.frame(fixture["Aside"]).midX == -350.5)
        #expect(layout.frame(fixture["Aside"]).midY == 260)
        #expect(layout.floatingTopicIDs == [fixture["Idea"], fixture["Aside"]])
        // The main tree is laid out as if the floating topics were not there.
        let treeOnly = LayoutFixture("""
        Root
          A
          B
        """)
        let tree = engine.layout(treeOnly.state, sizes: [:], options: options)
        #expect(layout.frame(fixture["A"]) == tree.frame(treeOnly["A"]))
        #expect(layout.frame(fixture["B"]) == tree.frame(treeOnly["B"]))
    }

    /// The branch grows to the right of the floating topic by the tree rules.
    @Test func childrenStackToTheRightOfTheFloatingTopic() throws {
        let fixture = Self.fixture()
        let layout = engine.layout(fixture.state, sizes: [:], options: options)
        let idea = layout.frame(fixture["Idea"])
        let first = layout.frame(fixture["I1"])
        let second = layout.frame(fixture["I2"])

        #expect(first.minX == idea.maxX + options.horizontalSpacing)
        #expect(second.minX == first.minX)
        #expect(second.minY == first.maxY + options.verticalSpacing)
        #expect((first.minY + second.maxY) / 2 == idea.midY)
        #expect(layout.nodes[fixture["I1"]]?.side == .right)
        #expect(layout.nodes[fixture["I1"]]?.depth == 2)
        let connector = try #require(layout.connectors[fixture["I1"]])
        #expect(connector.start == CGPoint(x: idea.maxX, y: idea.midY))
        #expect(connector.end == CGPoint(x: first.minX, y: first.midY))
    }

    @Test(arguments: BranchSides.allCases)
    func floatingBranchesIgnoreTheSideOption(_ sides: BranchSides) {
        let fixture = Self.fixture()
        let layout = engine.layout(fixture.state, sizes: [:], options: LayoutOptions(sides: sides))
        #expect(layout.nodes[fixture["I2"]]?.side == .right)
        #expect(layout.frame(fixture["I2"]).minX > layout.frame(fixture["Idea"]).maxX)
    }

    @Test func boundsAndCrossLinksIncludeFloatingTopics() {
        var fixture = Self.fixture()
        fixture.link("A", "I2")
        let layout = engine.layout(fixture.state, sizes: [:], options: options)
        #expect(layout.bounds.contains(layout.frame(fixture["Aside"])))
        #expect(layout.bounds.contains(layout.frame(fixture["I2"])))
        #expect(layout.crossLinks.count == 1)
    }

    @Test func collapsedFloatingTopicHidesItsBranch() {
        var fixture = Self.fixture()
        fixture.collapse("Idea")
        let layout = engine.layout(fixture.state, sizes: [:], options: options)
        #expect(layout.nodes[fixture["I1"]] == nil)
        #expect(layout.nodes[fixture["Idea"]]?.hiddenDescendantCount == 2)
    }

    /// Same input, same geometry, whatever order the dictionaries hold the nodes in.
    @Test func layoutIsDeterministic() {
        let fixture = Self.fixture()
        let reversed = GraphState(map: fixture.state.map, nodes: fixture.nodes.reversed(), edges: [])
        let first = engine.layout(fixture.state, sizes: [:], options: options)
        #expect(engine.layout(fixture.state, sizes: [:], options: options) == first)
        #expect(engine.layout(reversed, sizes: [:], options: options) == first)
    }

    /// Floating topics are ordered by creation time, then ID.
    @Test func floatingOrderFollowsCreation() throws {
        let fixture = Self.fixture()
        var nodes = fixture.nodes
        let index = try #require(nodes.firstIndex { $0.id == fixture["Aside"] })
        nodes[index].createdAt = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let state = GraphState(map: fixture.state.map, nodes: nodes, edges: [])
        let layout = engine.layout(state, sizes: [:], options: options)
        #expect(layout.floatingTopicIDs == [fixture["Aside"], fixture["Idea"]])
    }

    // MARK: Updates

    struct Edit: Sendable {
        let name: String
        let command: @Sendable (LayoutFixture) -> any GraphCommand
    }

    static let edits: [Edit] = [
        Edit(name: "add a floating topic") { _ in
            AddFloatingTopicCommand(title: "New", position: TopicPosition(x: 10, y: 600))
        },
        Edit(name: "move a floating topic") { f in
            MoveFloatingTopicCommand(nodeID: f["Idea"], to: TopicPosition(x: -800, y: 20))
        },
        Edit(name: "detach a main branch") { f in
            DetachBranchCommand(nodeID: f["A"], position: TopicPosition(x: 0, y: -700))
        },
        Edit(name: "detach a deep topic") { f in
            DetachBranchCommand(nodeID: f["I1"], position: TopicPosition(x: 900, y: 900))
        },
        Edit(name: "attach a floating topic") { f in
            ReparentNodeCommand(nodeID: f["Idea"], newParentID: f["B"])
        },
        Edit(name: "attach a floating topic to another") { f in
            ReparentNodeCommand(nodeID: f["Aside"], newParentID: f["I2"])
        },
        Edit(name: "delete a floating topic") { f in
            DeleteNodeCommand(nodeID: f["Idea"])
        },
        Edit(name: "add a child to a floating topic") { f in
            AddNodeCommand(.child(of: f["Aside"]), title: "New")
        },
        Edit(name: "collapse a floating topic") { f in
            UpdateNodeCommand(nodeID: f["Idea"], .isCollapsed(true))
        },
    ]

    /// An update after each floating edit, and after its undo and redo, is the
    /// same as a full layout.
    @Test(arguments: FloatingLayoutTests.edits.indices)
    func updateMatchesAFullLayout(_ index: Int) throws {
        let edit = Self.edits[index]
        let fixture = Self.fixture()
        var graph = try fixture.engine()
        let before = engine.layout(graph.state, sizes: [:], options: options)

        let changes = try graph.execute(edit.command(fixture))
        let updated = engine.update(before, graph: graph.state, sizes: [:], options: options, changed: changes.layoutInvalidation)
        #expect(updated == engine.layout(graph.state, sizes: [:], options: options), "\(edit.name)")

        let undoResult = graph.undo()
        let undone = try #require(undoResult)
        let afterUndo = engine.update(updated, graph: graph.state, sizes: [:], options: options, changed: undone.layoutInvalidation)
        #expect(afterUndo == before, "undo \(edit.name)")
        let redoResult = graph.redo()
        let redone = try #require(redoResult)
        let afterRedo = engine.update(afterUndo, graph: graph.state, sizes: [:], options: options, changed: redone.layoutInvalidation)
        #expect(afterRedo == updated, "redo \(edit.name)")
    }

    /// Random tree and floating edits chained, each update built on the last.
    @Test(arguments: [UInt64(21), 22, 23])
    func chainedFloatingEditsStayEqualToFullLayouts(seed: UInt64) throws {
        let fixture = LayoutFixture(randomTreeOf: 80, seed: 5)
        var graph = try fixture.engine()
        var layout = engine.layout(graph.state, sizes: [:], options: options)
        var random = SplitMix64(seed: seed)

        for step in 0..<60 {
            let ids = graph.state.nodes.keys.sorted()
            let target = ids[random.nextInt(below: ids.count)]
            let other = ids[random.nextInt(below: ids.count)]
            let position = TopicPosition(x: Double(random.nextInt(below: 2000)) - 1000, y: Double(random.nextInt(below: 2000)) - 1000)
            let newID = NodeID(UUID(uuidString: String(format: "00000000-0000-0000-0002-%012X", step))!)
            let command: any GraphCommand = switch random.nextInt(below: 6) {
            case 0: AddFloatingTopicCommand(nodeID: newID, title: "F\(step)", position: position)
            case 1: DetachBranchCommand(nodeID: target, position: position)
            case 2: MoveFloatingTopicCommand(nodeID: target, to: position)
            case 3: ReparentNodeCommand(nodeID: target, newParentID: other)
            case 4: AddNodeCommand(nodeID: newID, .child(of: target), title: "S\(step)")
            default: target == graph.state.map.rootNodeID ? AddNodeCommand(.child(of: target), title: "S\(step)") : DeleteNodeCommand(nodeID: target)
            }
            guard let changes = try? graph.execute(command) else { continue }
            layout = engine.update(layout, graph: graph.state, sizes: [:], options: options, changed: changes.layoutInvalidation)
            #expect(layout == engine.layout(graph.state, sizes: [:], options: options), "step \(step)")
        }
        #expect(!graph.state.floatingTopicIDs.isEmpty)
    }
}

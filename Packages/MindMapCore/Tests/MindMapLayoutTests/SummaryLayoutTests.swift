import CoreGraphics
import Foundation
import MindMapDomain
import MindMapGraph
@testable import MindMapLayout
import Testing

@Suite("Summaries in the layout")
struct SummaryLayoutTests {
    let engine = HorizontalTreeLayout()
    let options = LayoutOptions(sides: .rightOnly)

    static func fixture() -> LayoutFixture {
        LayoutFixture("""
        Root
          A
          B
            B1
            B2
          C
          D
        """)
    }

    private func graph(
        summary first: String,
        _ last: String,
        in fixture: LayoutFixture
    ) throws -> (graph: GraphEngine, group: GroupID, topic: NodeID) {
        var graph = try fixture.engine()
        let group = GroupID()
        let topic = NodeID()
        _ = try graph.execute(AddSummaryCommand(groupID: group, nodeID: topic, from: fixture[first], to: fixture[last], title: "Sum"))
        return (graph, group, topic)
    }

    @Test func bracketIsBeyondTheRunAndTheTopicBeyondTheBracket() throws {
        let fixture = Self.fixture()
        let (graph, group, topic) = try graph(summary: "B", "C", in: fixture)
        let layout = engine.layout(graph.state, sizes: [:], options: options)
        let bracket = try #require(layout.summaries[group])

        let run = ["B", "B1", "B2", "C"].map { layout.frame(fixture[$0]) }.reduce(CGRect.null) { $0.union($1) }
        #expect(bracket.side == .right)
        #expect(bracket.summaryNodeID == topic)
        #expect(bracket.frame.minX == run.maxX + options.summaryBracketGap)
        #expect(bracket.frame.width == options.summaryBracketWidth)
        #expect(bracket.frame.minY == run.minY)
        #expect(bracket.frame.maxY == run.maxY)

        let card = layout.frame(topic)
        #expect(card.minX == bracket.frame.maxX + options.horizontalSpacing)
        #expect(card.midY == bracket.tip.y)
        // The bracket stands in for the connector, and the topic is out of the column.
        #expect(layout.connectors[topic] == nil)
        #expect(layout.nodes[topic]?.depth == 1)
        #expect(layout.bounds.contains(card))
        #expect(layout.bounds.contains(bracket.frame))
        #expect(layout.overlappingPairs.isEmpty)
    }

    @Test func aRunOnTheLeftBracketsLeftward() throws {
        let fixture = Self.fixture()
        let (graph, group, topic) = try graph(summary: "A", "B", in: fixture)
        let left = LayoutOptions(sides: .leftOnly)
        let layout = engine.layout(graph.state, sizes: [:], options: left)
        let bracket = try #require(layout.summaries[group])

        let run = ["A", "B", "B1", "B2"].map { layout.frame(fixture[$0]) }.reduce(CGRect.null) { $0.union($1) }
        #expect(bracket.side == .left)
        #expect(bracket.frame.maxX == run.minX - left.summaryBracketGap)
        #expect(layout.frame(topic).maxX == bracket.frame.minX - left.horizontalSpacing)
    }

    /// A summary branch taller than its run pushes the neighbours apart, so
    /// nothing overlaps; one no taller leaves the column as it was.
    @Test func aTallSummaryBranchMakesRoom() throws {
        let fixture = Self.fixture()
        let plain = engine.layout(fixture.state, sizes: [:], options: options)
        var (graph, _, topic) = try graph(summary: "C", "C", in: fixture)
        let short = engine.layout(graph.state, sizes: [:], options: options)
        #expect(short.frame(fixture["D"]).minY - short.frame(fixture["C"]).maxY
            == plain.frame(fixture["D"]).minY - plain.frame(fixture["C"]).maxY)

        for index in 1...4 {
            _ = try graph.execute(AddNodeCommand(.child(of: topic), title: "S\(index)"))
        }
        let tall = engine.layout(graph.state, sizes: [:], options: options)
        #expect(tall.overlappingPairs.isEmpty)
        #expect(tall.frame(fixture["D"]).minY - tall.frame(fixture["C"]).maxY
            > plain.frame(fixture["D"]).minY - plain.frame(fixture["C"]).maxY)
    }

    @Test func outerBracketClearsAnInnerSummary() throws {
        let fixture = Self.fixture()
        var (graph, inner, innerTopic) = try graph(summary: "B", "C", in: fixture)
        let outer = GroupID()
        _ = try graph.execute(AddSummaryCommand(groupID: outer, from: fixture["A"], to: fixture["D"], title: "All"))
        let layout = engine.layout(graph.state, sizes: [:], options: options)

        let innerBracket = try #require(layout.summaries[inner])
        let outerBracket = try #require(layout.summaries[outer])
        #expect(outerBracket.frame.minX > layout.frame(innerTopic).maxX)
        #expect(outerBracket.frame.minX > innerBracket.frame.maxX)
        #expect(layout.overlappingPairs.isEmpty)
    }

    @Test func hiddenWithACollapsedParent() throws {
        let fixture = Self.fixture()
        // Adding the summary opens the branch, as adding any child does.
        var (graph, group, topic) = try graph(summary: "B1", "B2", in: fixture)
        _ = try graph.execute(UpdateNodeCommand(nodeID: fixture["B"], .isCollapsed(true)))
        let layout = engine.layout(graph.state, sizes: [:], options: options)

        #expect(layout.summaries[group] == nil)
        #expect(layout.nodes[topic] == nil)
    }

    @Test func isDeterministic() throws {
        let fixture = Self.fixture()
        let (graph, _, _) = try graph(summary: "A", "C", in: fixture)
        let sizes = variedSizes(for: graph.state, seed: 7)
        let first = engine.layout(graph.state, sizes: sizes, options: LayoutOptions())
        let second = engine.layout(graph.state, sizes: sizes, options: LayoutOptions())
        #expect(first == second)
    }

    /// Adding, growing, removing and undoing summaries through the engine
    /// keeps the incremental layout equal to a full one.
    @Test func updatesMatchAFullLayout() throws {
        let fixture = Self.fixture()
        var graph = try fixture.engine()
        var layout = engine.layout(graph.state, sizes: [:], options: options)
        let group = GroupID()
        let topic = NodeID()
        func step(_ changes: GraphChangeSet) {
            layout = engine.update(layout, graph: graph.state, sizes: [:], options: options, changed: changes.layoutInvalidation)
            #expect(layout == engine.layout(graph.state, sizes: [:], options: options))
        }
        step(try graph.execute(AddSummaryCommand(groupID: group, nodeID: topic, from: fixture["B"], to: fixture["C"])))
        step(try graph.execute(AddNodeCommand(.child(of: topic), title: "Detail")))
        step(try graph.execute(AddNodeCommand(.child(of: fixture["B1"]), title: "Wide branch grows")))
        step(try graph.execute(DeleteNodeCommand(nodeID: fixture["C"])))
        #expect(layout.summaries[group] != nil)
        let firstUndo = graph.undo()
        step(try #require(firstUndo))
        step(try graph.execute(DeleteNodeCommand(nodeIDs: [fixture["B"], fixture["C"]])))
        // No member left: the topic is back in the column as an ordinary child.
        #expect(layout.summaries.isEmpty)
        #expect(layout.connectors[topic] != nil)
        let secondUndo = graph.undo()
        step(try #require(secondUndo))
        step(try graph.execute(RemoveSummaryCommand(groupID: group)))
        #expect(layout.summaries.isEmpty)
        #expect(layout.nodes[topic] == nil)
    }
}

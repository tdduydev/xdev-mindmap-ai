import CoreGraphics
import Foundation
import MindMapDomain
import MindMapGraph
@testable import MindMapLayout
import Testing

@Suite("Boundaries in the layout")
struct BoundaryLayoutTests {
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

    private func graph(boundary first: String, _ last: String, title: String? = nil, in fixture: LayoutFixture) throws -> (GraphEngine, GroupID) {
        var graph = try fixture.engine()
        let id = GroupID()
        _ = try graph.execute(AddGroupCommand(groupID: id, from: fixture[first], to: fixture[last], title: title))
        return (graph, id)
    }

    @Test func frameHoldsTheMembersBranchesWithPadding() throws {
        let fixture = Self.fixture()
        let (graph, id) = try graph(boundary: "B", "C", in: fixture)
        let layout = engine.layout(graph.state, sizes: [:], options: options)
        let frame = try #require(layout.boundaries[id])

        for title in ["B", "B1", "B2", "C"] {
            #expect(frame.insetBy(dx: options.boundaryPadding, dy: options.boundaryPadding).contains(layout.frame(fixture[title])))
        }
        #expect(!frame.intersects(layout.frame(fixture["A"])))
        #expect(!frame.intersects(layout.frame(fixture["D"])))
        #expect(layout.bounds.contains(frame))
    }

    /// The run's neighbours move apart by the padding, and by the title's room above.
    @Test func neighboursMakeRoomForPaddingAndTitle() throws {
        let fixture = Self.fixture()
        let plain = engine.layout(fixture.state, sizes: [:], options: options)
        let (graph, id) = try graph(boundary: "C", "C", title: "Phase 1", in: fixture)
        let layout = engine.layout(graph.state, sizes: [:], options: options)

        let gapAbove = layout.frame(fixture["C"]).minY - layout.frame(fixture["B2"]).maxY
        let plainAbove = plain.frame(fixture["C"]).minY - plain.frame(fixture["B2"]).maxY
        #expect(gapAbove == plainAbove + options.boundaryPadding + options.boundaryTitleHeight)
        let gapBelow = layout.frame(fixture["D"]).minY - layout.frame(fixture["C"]).maxY
        let plainBelow = plain.frame(fixture["D"]).minY - plain.frame(fixture["C"]).maxY
        #expect(gapBelow == plainBelow + options.boundaryPadding)

        let frame = try #require(layout.boundaries[id])
        #expect(frame.minY == layout.frame(fixture["C"]).minY - options.boundaryPadding - options.boundaryTitleHeight)
    }

    @Test func hiddenWithACollapsedParentAndAroundACollapsedMember() throws {
        var fixture = Self.fixture()
        fixture.collapse("B")
        let (graph, id) = try graph(boundary: "B1", "B2", in: fixture)
        #expect(engine.layout(graph.state, sizes: [:], options: options).boundaries[id] == nil)

        let (outer, outerID) = try self.graph(boundary: "B", "B", in: fixture)
        let layout = engine.layout(outer.state, sizes: [:], options: options)
        let frame = try #require(layout.boundaries[outerID])
        #expect(frame == layout.frame(fixture["B"]).insetBy(dx: -options.boundaryPadding, dy: -options.boundaryPadding))
    }

    @Test func outerFrameTakesInANestedBoundary() throws {
        let fixture = Self.fixture()
        var (graph, inner) = try graph(boundary: "B1", "B2", in: fixture)
        let outer = GroupID()
        _ = try graph.execute(AddGroupCommand(groupID: outer, from: fixture["B"], to: fixture["C"]))
        let layout = engine.layout(graph.state, sizes: [:], options: options)
        let innerFrame = try #require(layout.boundaries[inner])
        let outerFrame = try #require(layout.boundaries[outer])
        #expect(outerFrame.contains(innerFrame))
    }

    /// Adding, renaming, removing and undoing boundaries through the engine
    /// keeps the incremental layout equal to a full one.
    @Test func updatesMatchAFullLayout() throws {
        let fixture = Self.fixture()
        var graph = try fixture.engine()
        var layout = engine.layout(graph.state, sizes: [:], options: options)
        let id = GroupID()
        func step(_ changes: GraphChangeSet) {
            layout = engine.update(layout, graph: graph.state, sizes: [:], options: options, changed: changes.layoutInvalidation)
            #expect(layout == engine.layout(graph.state, sizes: [:], options: options))
        }
        step(try graph.execute(AddGroupCommand(groupID: id, from: fixture["B"], to: fixture["C"])))
        step(try graph.execute(UpdateGroupCommand(groupID: id, title: .set("Plan"))))
        step(try graph.execute(DeleteNodeCommand(nodeID: fixture["C"])))
        #expect(layout.boundaries[id] != nil)
        let undone = graph.undo()
        step(try #require(undone))
        step(try graph.execute(RemoveGroupCommand(groupID: id)))
        #expect(layout.boundaries.isEmpty)
    }
}

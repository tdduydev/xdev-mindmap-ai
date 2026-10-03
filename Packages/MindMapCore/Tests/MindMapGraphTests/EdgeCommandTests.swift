import Foundation
import MindMapDomain
@testable import MindMapGraph
import Testing

@Suite("Connection label and style")
struct EdgeCommandTests {
    static let outline = """
    Root
      A
      B
    """

    static func connected() throws -> (GraphFixture, EdgeID) {
        var fixture = try GraphFixture(outline)
        let id = EdgeID()
        try fixture.engine.execute(ConnectNodesCommand(edgeID: id, from: fixture["A"], to: fixture["B"]))
        return (fixture, id)
    }

    @Test func labelAndStyleAreEachOneUndoStep() throws {
        var (fixture, id) = try Self.connected()

        try expectUndoAndRedo(UpdateEdgeCommand(edgeID: id, label: .set("  depends on \n")), on: &fixture)
        #expect(fixture.state.edges[id]?.label == "depends on")

        try expectUndoAndRedo(UpdateEdgeCommand(
            edgeID: id, lineStyle: .set(.solid), arrowHeads: .set(.both), color: .set(.rose)
        ), on: &fixture)
        let edge = try #require(fixture.state.edges[id])
        #expect(edge.lineStyle == .solid)
        #expect(edge.arrowHeads == .both)
        #expect(edge.color == .rose)
        #expect(edge.label == "depends on", "fields left at .keep stay")
    }

    @Test func blankLabelClearsIt() throws {
        var (fixture, id) = try Self.connected()
        try fixture.engine.execute(UpdateEdgeCommand(edgeID: id, label: .set("see")))
        try expectUndoAndRedo(UpdateEdgeCommand(edgeID: id, label: .set("   ")), on: &fixture)
        #expect(fixture.state.edges[id]?.label == nil)
    }

    @Test func nilStyleBringsBackTheDefaultLook() throws {
        var (fixture, id) = try Self.connected()
        try fixture.engine.execute(UpdateEdgeCommand(edgeID: id, lineStyle: .set(.dotted)))
        try expectUndoAndRedo(UpdateEdgeCommand(edgeID: id, lineStyle: .set(nil)), on: &fixture)
        #expect(fixture.state.edges[id]?.lineStyle == nil)
    }

    @Test func sameValueChangesNothing() throws {
        var (fixture, id) = try Self.connected()
        let changes = try fixture.engine.execute(UpdateEdgeCommand(edgeID: id, label: .set(nil), color: .set(nil)))
        #expect(changes.isEmpty)
    }

    @Test func reverseSwapsTheEnds() throws {
        var (fixture, id) = try Self.connected()
        try expectUndoAndRedo(ReverseEdgeCommand(edgeID: id), on: &fixture)
        #expect(fixture.state.edges[id]?.sourceNodeID == fixture["B"])
        #expect(fixture.state.edges[id]?.targetNodeID == fixture["A"])
        #expect(GraphValidator.validate(fixture.state).isEmpty)
    }

    @Test func reverseRefusesToDuplicateTheOppositeLink() throws {
        var (fixture, id) = try Self.connected()
        let back = EdgeID()
        try fixture.engine.execute(ConnectNodesCommand(edgeID: back, from: fixture["B"], to: fixture["A"]))
        #expect(throws: GraphError.edgeAlreadyExists(back)) {
            try fixture.engine.execute(ReverseEdgeCommand(edgeID: id))
        }
    }

    @Test func missingEdgeThrows() throws {
        var (fixture, _) = try Self.connected()
        let missing = EdgeID()
        #expect(throws: GraphError.edgeNotFound(missing)) {
            try fixture.engine.execute(UpdateEdgeCommand(edgeID: missing, label: .set("x")))
        }
    }
}

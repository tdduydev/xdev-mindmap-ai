import Foundation
import MindMapDomain
import MindMapGraph
import Testing

@Suite("Changing the theme")
struct ChangeThemeCommandTests {
    @Test func newMapStartsWithTheThemeItIsGiven() throws {
        #expect(GraphState.newMap(title: "Plan").map.theme == .standard)
        // The theme for new maps is only a start: undoing a later change goes back to it, not to Standard.
        var engine = try GraphEngine(state: GraphState.newMap(title: "Plan", theme: .xdevBlue))
        try engine.execute(ChangeThemeCommand(theme: .graphite))
        #expect(engine.undo() != nil)
        #expect(engine.state.map.theme == .xdevBlue)
        #expect(engine.redo() != nil)
        #expect(engine.state.map.theme == .graphite)
    }

    @Test func changesOnlyTheMapTheme() throws {
        var engine = try GraphEngine(state: GraphState.newMap(title: "Plan"))
        let nodesBefore = engine.state.nodes

        let changes = try engine.execute(ChangeThemeCommand(theme: .graphite))

        #expect(engine.state.map.theme == .graphite)
        #expect(changes.map?.before?.theme == .standard)
        #expect(changes.map?.after?.theme == .graphite)
        #expect(changes.nodes.isEmpty)
        #expect(changes.edges.isEmpty)
        #expect(engine.state.nodes == nodesBefore)
    }

    @Test func undoRestoresAndRedoReapplies() throws {
        var engine = try GraphEngine(state: GraphState.newMap(title: "Plan"))
        try engine.execute(ChangeThemeCommand(theme: .xdevBlue))
        try engine.execute(ChangeThemeCommand(theme: .graphite))

        #expect(engine.undo() != nil)
        #expect(engine.state.map.theme == .xdevBlue)
        #expect(engine.undo() != nil)
        #expect(engine.state.map.theme == .standard)
        #expect(engine.redo() != nil)
        #expect(engine.state.map.theme == .xdevBlue)
        #expect(engine.redo() != nil)
        #expect(engine.state.map.theme == .graphite)
    }

    /// Picking the theme the map already has must not leave an empty undo step.
    @Test func sameThemeChangesNothing() throws {
        var engine = try GraphEngine(state: GraphState.newMap(title: "Plan"))

        let changes = try engine.execute(ChangeThemeCommand(theme: .standard))

        #expect(changes.isEmpty)
    }
}

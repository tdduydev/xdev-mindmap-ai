import Foundation
import MindMapDomain
import MindMapGraph
@testable import MindMapInterchange
import Testing

@Suite("Connections in Markdown")
struct ConnectionInterchangeTests {
    static func connectedMap() throws -> GraphState {
        var engine = try GraphEngine(state: GraphState.imported(from: OutlineDraft(items: [
            .init(depth: 0, title: "Plan"),
            .init(depth: 1, title: "Budget"),
            .init(depth: 1, title: "Launch"),
            .init(depth: 2, title: "Ads"),
        ]), title: "Plan"))
        let ids = Dictionary(uniqueKeysWithValues: engine.state.nodes.values.map { ($0.title, $0.id) })
        try engine.execute(ConnectNodesCommand(from: ids["Launch"]!, to: ids["Budget"]!, label: "depends on"))
        try engine.execute(ConnectNodesCommand(from: ids["Ads"]!, to: ids["Plan"]!))
        return engine.state
    }

    @Test func exportEndsWithTheConnectionsWhenAsked() throws {
        let text = try MarkdownOutline.export(Self.connectedMap(), options: .init(headingLevels: 1, connectionsTitle: "Connections:"))
        #expect(text.hasSuffix("""
        - Ads

        ---

        Connections:

        - Launch → Budget: depends on
        - Ads → Plan

        """))
    }

    @Test func copyLeavesThemOut() throws {
        let text = try MarkdownOutline.export(Self.connectedMap())
        #expect(!text.contains("→"))
    }

    @Test func aBranchExportsOnlyConnectionsInsideIt() throws {
        let state = try Self.connectedMap()
        let launch = try #require(state.nodes.values.first { $0.title == "Launch" })
        let text = try MarkdownOutline.export(state, branch: launch.id, options: .init(connectionsTitle: "Connections:"))
        #expect(!text.contains("Connections:"))
    }

    @Test func importDropsTheConnectionsBlock() throws {
        let text = try MarkdownOutline.export(Self.connectedMap(), options: .init(headingLevels: 1, connectionsTitle: "Kết nối:"))
        let draft = MarkdownOutline.parse(text)
        #expect(draft.items.map(\.title) == ["Plan", "Budget", "Launch", "Ads"])
        #expect(draft.items.allSatisfy { $0.note == nil })
    }

    @Test func anOrdinaryListAfterARuleIsStillRead() {
        let draft = MarkdownOutline.parse("# Plan\n\n---\n\nNext:\n\n- Ship\n")
        #expect(draft.items.map(\.title) == ["Plan", "Ship"])
    }
}

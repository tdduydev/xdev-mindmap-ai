import Foundation
import MindMapDomain
import MindMapGraph
@testable import MindMapInterchange
import Testing

@Suite("Topic links in Markdown, plain text and backups")
struct TopicLinkInterchangeTests {
    static func linkedMap() throws -> GraphState {
        try GraphState.imported(from: OutlineDraft(items: [
            .init(depth: 0, title: "Plan", link: TopicLink(string: "https://example.com/plan")),
            .init(depth: 1, title: "Mail [team]", link: TopicLink(string: "mailto:team@example.com")),
            .init(depth: 1, title: "Docs", link: TopicLink(string: "https://example.com/a_(b)")),
            .init(depth: 2, title: "Plain"),
            .init(depth: 2, title: "[looks](https://example.com)"),
        ]), title: "Plan")
    }

    @Test func markdownWritesTitlesAsLinks() throws {
        let text = try MarkdownOutline.export(Self.linkedMap(), options: .init(headingLevels: 1))
        #expect(text == """
        # [Plan](https://example.com/plan)

        - [Mail \\[team\\]](mailto:team@example.com)
        - [Docs](https://example.com/a_\\(b\\))
          - Plain
          - \\[looks](https://example.com)

        """)
    }

    @Test(arguments: [0, 1, 2])
    func markdownReadsLinksBack(headingLevels: Int) throws {
        let graph = try Self.linkedMap()
        let text = try MarkdownOutline.export(graph, options: .init(headingLevels: headingLevels))
        let draft = MarkdownOutline.parse(text)

        #expect(draft.items.map(\.title) == ["Plan", "Mail [team]", "Docs", "Plain", "[looks](https://example.com)"])
        #expect(draft.items.map(\.link?.string) == [
            "https://example.com/plan", "mailto:team@example.com", "https://example.com/a_(b)", nil, nil,
        ])
    }

    @Test func otherInlineLinksStayText() {
        let draft = MarkdownOutline.parse("""
        - See [docs](https://example.com) first
        - [Script](javascript:alert(1))
        - [Nested [x]](https://example.com)
        - [Open](https://example.com)
        """)
        #expect(draft.items.map(\.link) == [nil, nil, nil, TopicLink(string: "https://example.com")])
        #expect(draft.items[0].title == "See [docs](https://example.com) first")
        #expect(draft.items[3].title == "Open")
    }

    @Test func plainTextWritesAndReadsATrailingLink() throws {
        let graph = try Self.linkedMap()
        let text = try PlainTextOutline.export(graph)
        #expect(text.hasPrefix("Plan <https://example.com/plan>\n\tMail [team] <mailto:team@example.com>\n"))

        let draft = PlainTextOutline.parse(text)
        #expect(draft.items.map(\.title) == ["Plan", "Mail [team]", "Docs", "Plain", "[looks](https://example.com)"])
        #expect(draft.items.map(\.link?.string) == [
            "https://example.com/plan", "mailto:team@example.com", "https://example.com/a_(b)", nil, nil,
        ])
        #expect(PlainTextOutline.parse("Arrow <- here >\nFile <file:///x>").items.map(\.link) == [nil, nil])
    }

    @Test func pastingIntoAMapKeepsLinksAsOneUndoStep() throws {
        var engine = try GraphEngine(state: GraphState.imported(from: OutlineDraft(items: [.init(depth: 0, title: "Root")]), title: "Root"))
        let rootID = try #require(engine.state.map.rootNodeID)
        let before = engine.state
        let draft = MarkdownOutline.parse("- [Site](https://example.com)\n  - Child\n")

        try engine.execute(InsertOutlineCommand(draft, under: rootID))
        #expect(engine.state.firstNode(titled: "Site")?.link == TopicLink(string: "https://example.com"))
        engine.undo()
        #expect(sameContent(engine.state, before))
        engine.redo()
        #expect(engine.state.firstNode(titled: "Site")?.link == TopicLink(string: "https://example.com"))
    }

    @Test func backupKeepsLinks() async throws {
        let graph = try Self.linkedMap()
        let restored = try await MapArchive.decode(MapArchive.exportData(graph)).graph
        #expect(Set(restored.nodes.values.compactMap(\.link)) == Set(graph.nodes.values.compactMap(\.link)))
        #expect(restored.nodes == graph.nodes)
    }
}

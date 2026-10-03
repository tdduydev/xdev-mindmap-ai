import Foundation
import MindMapDomain
import MindMapGraph
@testable import MindMapInterchange
import Testing

@Suite("Topic symbols and colours in Markdown and plain text")
struct TopicSymbolInterchangeTests {
    /// "Plan" 🚀 and blue, "Risks" flag (an SF Symbol), "Done" ✅ with a link, "Blank" 💡 with no title.
    static func styledMap() throws -> GraphState {
        let state = try GraphState.imported(from: OutlineDraft(items: [
            .init(depth: 0, title: "Plan"),
            .init(depth: 1, title: "Risks"),
            .init(depth: 1, title: "Done", link: TopicLink(string: "https://example.com")),
            .init(depth: 1, title: ""),
        ]), title: "Plan")
        var engine = try GraphEngine(state: state)
        let ids = state.readingOrder().map(\.id)
        try engine.execute(SetNodeStyleCommand(nodeIDs: [ids[0]], color: .set(.blue), symbol: .set("🚀")))
        try engine.execute(SetNodeStyleCommand(nodeIDs: [ids[1]], symbol: .set("flag.fill")))
        try engine.execute(SetNodeStyleCommand(nodeIDs: [ids[2]], symbol: .set("✅")))
        try engine.execute(SetNodeStyleCommand(nodeIDs: [ids[3]], symbol: .set("💡")))
        return engine.state
    }

    @Test func markdownWritesTheEmojiBeforeTheTitle() throws {
        let text = try MarkdownOutline.export(Self.styledMap(), options: .init(headingLevels: 1))
        #expect(text == """
        # 🚀 Plan

        - Risks
        - [✅ Done](https://example.com)
        - 💡

        """)
    }

    @Test func plainTextWritesTheEmojiBeforeTheTitle() throws {
        let text = try PlainTextOutline.export(Self.styledMap())
        #expect(text == "🚀 Plan\n\tRisks\n\t✅ Done <https://example.com>\n\t💡\n")
    }

    @Test func emojiIsOnlyANonSymbolName() {
        #expect(TopicSymbol.emoji("🔥") == "🔥")
        #expect(TopicSymbol.emoji("star.fill") == nil)
        #expect(TopicSymbol.emoji(nil) == nil)
        #expect(TopicSymbol.emoji("") == nil)
    }
}

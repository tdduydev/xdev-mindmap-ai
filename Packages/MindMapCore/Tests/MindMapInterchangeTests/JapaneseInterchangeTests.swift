import Foundation
import MindMapDomain
import MindMapGraph
@testable import MindMapInterchange
import Testing

/// Japanese text leaves and comes back exactly as written (MM-94): no width,
/// kana or composition changes, since a file is the person's own words.
@Suite("Japanese interchange")
struct JapaneseInterchangeTests {
    /// Half-width katakana and a decomposed voiced mark are kept as they are,
    /// not widened or composed.
    private let draft = OutlineDraft(items: [
        .init(depth: 0, title: "東京旅行の計画", note: "予算は１０万円。\n\n航空券を先に予約する。"),
        .init(depth: 1, title: "ｶﾞｲﾄﾞﾌﾞｯｸ"),
        .init(depth: 2, title: "か\u{3099}いど", note: "全角　スペース"),
        .init(depth: 1, title: "MacBookで「メモ」を書く"),
    ])

    @Test(arguments: InterchangeFormat.allCases)
    func outlinesKeepEveryScalar(format: InterchangeFormat) async throws {
        let state = try GraphState.imported(from: draft, title: "")

        let data = try await format.exportData(state)
        let reread = try await format.parse(data)

        #expect(reread == draft)
        #expect(reread.items.map { Array($0.title.unicodeScalars) } == draft.items.map { Array($0.title.unicodeScalars) })
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("ｶﾞｲﾄﾞﾌﾞｯｸ"))
    }

    @Test func archiveKeepsEveryScalar() async throws {
        let graph = try GraphState.imported(from: draft, title: "旅行")

        let data = try await MapArchive.exportData(graph)
        let restored = try await MapArchive.decode(data).graph

        #expect(restored.map == graph.map)
        #expect(restored.nodes == graph.nodes)
        let titles = Set(restored.nodes.values.map { Array($0.title.unicodeScalars) })
        #expect(titles.contains(Array("か\u{3099}いど".unicodeScalars)))
        #expect(titles.contains(Array("ｶﾞｲﾄﾞﾌﾞｯｸ".unicodeScalars)))
        // UTF-8 as written, not \u escapes, so the file reads in any editor.
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("東京旅行の計画"))
    }
}

import Foundation
import MindMapDomain
import MindMapGraph
@testable import MindMapInterchange
import Testing

@Suite("Interchange formats and decoding")
struct InterchangeFormatTests {
    @Test func formatComesFromTheFileExtension() {
        #expect(InterchangeFormat(fileExtension: "MD") == .markdown)
        #expect(InterchangeFormat(fileExtension: "markdown") == .markdown)
        #expect(InterchangeFormat(fileExtension: "txt") == .plainText)
        #expect(InterchangeFormat(fileExtension: "opml") == nil)
    }

    @Test func utf8WithAndWithoutAByteOrderMarkDecodes() throws {
        let text = "Kế hoạch\n\tMục tiêu\n"

        #expect(try InterchangeText.decode(Data(text.utf8)) == text)
        #expect(try InterchangeText.decode(Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)) == text)
    }

    @Test func utf16WithAByteOrderMarkDecodes() throws {
        let text = "Kế hoạch\n"
        let data = try #require(text.data(using: .utf16))

        #expect(try InterchangeText.decode(data) == text)
    }

    @Test(arguments: [
        Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x01]),
        Data([0x4B, 0xE1, 0x7A]),
    ])
    func binaryAndLegacyEncodingsAreRefused(data: Data) {
        #expect(throws: InterchangeError.unreadableText) {
            try InterchangeText.decode(data)
        }
    }

    @Test func parsingDataRunsTheSameParser() async throws {
        let draft = try await InterchangeFormat.markdown.parse(Data("# Plan\n- Goals\n".utf8))

        #expect(draft.outline == "Plan\n  Goals")
    }

    @Test(arguments: InterchangeFormat.allCases)
    func exportedDataReadsBackAsTheSameMap(format: InterchangeFormat) async throws {
        let draft = OutlineDraft(items: [
            .init(depth: 0, title: "Plan", note: "Why"),
            .init(depth: 1, title: "Goals"),
            .init(depth: 2, title: "Ship", note: "Soon\n\nReally"),
            .init(depth: 1, title: "Risks"),
        ])
        let state = try GraphState.imported(from: draft, title: "")

        let data = try await format.exportData(state)
        let reread = try await format.parse(data)

        #expect(reread == draft)
    }

    @Test(arguments: InterchangeFormat.allCases)
    func exportWithoutNotesDropsThem(format: InterchangeFormat) async throws {
        let state = try GraphState.imported(
            from: OutlineDraft(items: [.init(depth: 0, title: "Plan", note: "Secret")]),
            title: ""
        )

        let text = try format.export(state, includeNotes: false)

        #expect(!text.contains("Secret"))
    }
}

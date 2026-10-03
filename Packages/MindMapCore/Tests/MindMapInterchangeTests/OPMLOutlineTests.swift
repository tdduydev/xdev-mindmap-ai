import Foundation
import MindMapDomain
import MindMapGraph
import Testing
@testable import MindMapInterchange

/// Fixtures are written for these tests from the OPML 2.0 spec
/// (opml.org/spec2.opml) and its examples' shapes; no file from another app
/// is copied, since none came with a licence to ship it.
@Suite struct OPMLOutlineTests {
    private func parse(_ xml: String) throws -> OPMLOutline.Document {
        try OPMLOutline.parse(Data(xml.utf8))
    }

    @Test func readsNestedOutlinesTitlesAndNotes() throws {
        let document = try parse("""
            <?xml version="1.0" encoding="ISO-8859-1"?>
            <opml version="2.0">
              <head>
                <title>Plan</title>
                <dateCreated>Mon, 31 Oct 2005 19:23:00 GMT</dateCreated>
                <expansionState>1, 6</expansionState>
              </head>
              <body>
                <outline text="Goals" _note="Why we&#10;do this">
                  <outline text="Ship 1.1"/>
                  <outline text="Grow">
                    <outline text="Japan"/>
                  </outline>
                </outline>
                <outline text="Risks"/>
              </body>
            </opml>
            """)
        #expect(document.title == "Plan")
        #expect(document.draft.outline == """
            Goals [Why we
            do this]
              Ship 1.1
              Grow
                Japan
            Risks
            """)
        #expect(document.report.isEmpty)
    }

    @Test func skipsUnknownAttributesAndElements() throws {
        let document = try parse("""
            <opml version="2.0" xmlns:x="urn:example">
              <head><title>T</title><x:window top="1"/></head>
              <body>
                <outline text="A" created="Mon, 31 Oct 2005" _status="checked" isComment="true" x:color="red">
                  <x:extra><outline text="Not part of the tree"/></x:extra>
                  <outline text="B" isBreakpoint="true"/>
                </outline>
              </body>
            </opml>
            """)
        #expect(document.draft.outline == "A\n  B")
    }

    @Test func readsOPMLOneAndMissingText() throws {
        let document = try parse("""
            <opml version="1.0"><head/><body><outline><outline text="child"/></outline></body></opml>
            """)
        #expect(document.title == nil)
        #expect(document.draft.outline == "\n  child")
    }

    @Test func readsLinksAndReportsIncludedOutlines() throws {
        let document = try parse("""
            <opml version="2.0"><body>
              <outline text="Site" type="link" url="https://xdev.asia"/>
              <outline text="Feed" type="rss" xmlUrl="https://example.com/feed.xml" htmlUrl="https://example.com"/>
              <outline text="Shared list" type="include" url="https://example.com/list.opml"/>
              <outline text="Local" type="link" url="file:///Users/a/notes.txt"/>
            </body></opml>
            """)
        let items = document.draft.items
        #expect(items.map(\.link?.string) == [
            "https://xdev.asia", "https://example.com", "https://example.com/list.opml", nil,
        ])
        // A link this build does not open is kept as text, not dropped.
        #expect(items[3].note == "file:///Users/a/notes.txt")
        #expect(document.report.entries == [ImportReport.Entry(loss: .includedOutline, count: 1)])
    }

    @Test func refusesOtherXMLAndBrokenFiles() {
        #expect(throws: ForeignImportError.wrongFormat) {
            try parse(#"<?xml version="1.0"?><rss version="2.0"><channel/></rss>"#)
        }
        #expect(throws: ForeignImportError.damaged) {
            try parse(#"<opml version="2.0"><body><outline text="A"></body></opml>"#)
        }
        #expect(throws: ForeignImportError.damaged) {
            try OPMLOutline.parse(Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x01]))
        }
        #expect(throws: ForeignImportError.emptyDocument) {
            try parse(#"<opml version="2.0"><head><title>Empty</title></head><body/></opml>"#)
        }
    }

    @Test func readsUTF16() throws {
        var data = Data([0xFF, 0xFE])
        let xml = #"<?xml version="1.0" encoding="UTF-16"?><opml version="2.0"><body><outline text="Việc 日本"/></body></opml>"#
        data.append(xml.data(using: .utf16LittleEndian)!)
        #expect(try OPMLOutline.parse(data).draft.outline == "Việc 日本")
    }

    @Test func deepNestingReadsWithoutRecursion() throws {
        let depth = 2_000
        let xml = "<opml version=\"2.0\"><body>"
            + (0..<depth).map { "<outline text=\"\($0)\">" }.joined()
            + String(repeating: "</outline>", count: depth) + "</body></opml>"
        let items = try parse(xml).draft.items
        #expect(items.count == depth)
        #expect(items.last?.depth == depth - 1)
    }

    // MARK: Export

    private func sampleMap() throws -> GraphState {
        let draft = OutlineDraft(items: [
            .init(depth: 0, title: "Plan & \"Goals\"", note: "Line one\n\tindented <b>\n\nafter blank"),
            .init(depth: 1, title: "Ship", link: TopicLink(string: "https://xdev.asia/a?b=1&c=2")),
            .init(depth: 2, title: "Japan 日本"),
            .init(depth: 1, title: "Việc"),
        ])
        return try GraphState.imported(from: draft, title: "unused", now: fixedDate)
    }

    @Test func writesOPMLTwo() throws {
        let text = try OPMLOutline.export(sampleMap())
        #expect(text == """
            <?xml version="1.0" encoding="UTF-8"?>
            <opml version="2.0">
              <head>
                <title>Plan &amp; "Goals"</title>
              </head>
              <body>
                <outline text="Plan &amp; &quot;Goals&quot;" _note="Line one&#10;&#9;indented &lt;b&gt;&#10;&#10;after blank">
                  <outline text="Ship" type="link" url="https://xdev.asia/a?b=1&amp;c=2">
                    <outline text="Japan 日本"/>
                  </outline>
                  <outline text="Việc"/>
                </outline>
              </body>
            </opml>

            """)
    }

    @Test func leavesOutNotesWhenAskedAndExportsABranch() throws {
        let map = try sampleMap()
        let ship = try #require(map.firstNode(titled: "Ship"))
        let text = try OPMLOutline.export(map, branch: ship.id, includeNotes: false)
        #expect(text.contains(#"<outline text="Ship" type="link" url="https://xdev.asia/a?b=1&amp;c=2">"#))
        #expect(!text.contains(#"outline text="Plan"#))
        #expect(!text.contains("_note"))
    }

    @Test func dropsCharactersXMLCannotHold() throws {
        let draft = OutlineDraft(items: [.init(depth: 0, title: "a\u{1}b\u{FFFE}c")])
        let map = try GraphState.imported(from: draft, title: "t", now: fixedDate)
        let text = try OPMLOutline.export(map)
        #expect(try OPMLOutline.parse(Data(text.utf8)).draft.outline == "abc")
    }

    // MARK: Round trip

    @Test func mapToOPMLToMapKeepsTopicsNotesAndLinks() async throws {
        let map = try sampleMap()
        let data = try await OPMLOutline.exportData(map)
        let imported = try await ForeignFormat.opml.read(data, fileName: "file", now: fixedDate)
        let back = try #require(imported.maps.first)
        #expect(back.outline == map.outline)
        #expect(back.map.title == map.map.title)
        #expect(back.firstNode(titled: "Ship")?.link == TopicLink(string: "https://xdev.asia/a?b=1&c=2"))
        #expect(imported.report.isEmpty)
    }

    @Test func opmlToMapToOPMLKeepsTheFile() async throws {
        let original = """
            <?xml version="1.0" encoding="UTF-8"?>
            <opml version="2.0">
              <head>
                <title>Trip</title>
              </head>
              <body>
                <outline text="Trip" _note="Two weeks">
                  <outline text="Tokyo">
                    <outline text="Shibuya"/>
                    <outline text="Asakusa" type="link" url="https://example.com/asakusa"/>
                  </outline>
                  <outline text="Kyoto"/>
                </outline>
              </body>
            </opml>

            """
        let imported = try await ForeignFormat.opml.read(Data(original.utf8), fileName: "trip", now: fixedDate)
        let map = try #require(imported.maps.first)
        #expect(try OPMLOutline.export(map) == original)
    }

    @Test func severalTopLevelOutlinesGoUnderACentralTopicNamedByTheHead() async throws {
        let xml = #"<opml version="2.0"><head><title>Inbox</title></head><body><outline text="A"/><outline text="B"/></body></opml>"#
        let map = try #require(try await ForeignFormat.opml.read(Data(xml.utf8), fileName: "file", now: fixedDate).maps.first)
        #expect(map.outline == "Inbox\n  A\n  B")
        let untitled = #"<opml version="2.0"><body><outline text="A"/><outline text="B"/></body></opml>"#
        let named = try #require(try await ForeignFormat.opml.read(Data(untitled.utf8), fileName: "List", now: fixedDate).maps.first)
        #expect(named.outline == "List\n  A\n  B")
        #expect(named.nodes.values.allSatisfy { $0.metadata.origin == .imported })
    }

    @Test func formatByExtension() {
        #expect(ForeignFormat(fileExtension: "OPML") == .opml)
        #expect(ForeignFormat(fileExtension: "md") == nil)
    }

    @Test func reportCountsAndOrders() {
        var report = ImportReport()
        report.record(.attachment, count: 2)
        report.record(.image)
        report.record(.image, count: 0)
        var other = ImportReport()
        other.record(.image, count: 2)
        report.merge(other)
        #expect(report.entries == [.init(loss: .image, count: 3), .init(loss: .attachment, count: 2)])
        #expect(ImportReport().isEmpty)
    }
}

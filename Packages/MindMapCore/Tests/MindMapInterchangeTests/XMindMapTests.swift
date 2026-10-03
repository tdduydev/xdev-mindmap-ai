import Foundation
import MindMapDomain
import MindMapGraph
import Testing
@testable import MindMapInterchange

/// Fixtures are written for these tests from the published shapes of the two
/// layouts: `content.json` as the XMind SDK models it
/// (github.com/xmindltd/xmind-sdk-js) and XMind 8's `content.xml`
/// (github.com/xmindltd/xmind/wiki/XMindFileFormat). No file made by XMind
/// is copied, since none came with a licence to ship it.
@Suite struct XMindMapTests {
    private func read(_ data: Data, limits: XMindMap.ZipLimits = .standard) throws(ForeignImportError) -> ForeignImport {
        try XMindMap.read(data, fileName: "Plans", limits: limits)
    }

    private func readError(_ data: Data, limits: XMindMap.ZipLimits = .standard) -> ForeignImportError? {
        do {
            _ = try read(data, limits: limits)
            return nil
        } catch {
            return error
        }
    }

    private static let fullJSON = """
        [{
          "id": "sheet-1", "class": "sheet", "title": "Sheet 1",
          "rootTopic": {
            "id": "root", "class": "topic", "title": "Launch", "structureClass": "org.xmind.ui.logic.right",
            "notes": { "plain": { "content": "Why we ship" }, "realHTML": { "content": "<div>Why we ship</div>" } },
            "children": {
              "attached": [
                { "id": "a", "title": "Design", "labels": ["UI", "Q3"], "href": "https://example.com/design",
                  "markers": [{ "markerId": "priority-1" }, { "markerId": "task-done" }, { "markerId": "flag-red" }],
                  "image": { "src": "xap:resources/pic.png", "width": 80, "height": 60 },
                  "children": { "attached": [ { "id": "a1", "title": "Sketch" }, { "id": "a2", "title": "Review" } ],
                                "callout": [ { "id": "c1", "title": "Ask Kim" } ] },
                  "summaries": [ { "id": "s-1", "range": "(0,1)", "topicId": "sum" } ],
                  "boundaries": [ { "id": "b-1", "range": "(0,1)", "title": "Week 1" } ] },
                { "id": "b", "title": "Build", "href": "xmind:#a",
                  "boundaries": [ { "id": "b-2", "range": "master" } ] },
                { "id": "c", "title": "Spec", "href": "xap:attachments/spec.pdf" }
              ],
              "detached": [ { "id": "f", "title": "Parking lot", "position": { "x": -320, "y": 180 },
                              "children": { "attached": [ { "id": "f1", "title": "Maybe later" } ] } } ]
            }
          },
          "relationships": [ { "id": "r1", "end1Id": "c", "end2Id": "b", "title": "feeds" },
                             { "id": "r2", "end1Id": "c", "end2Id": "missing" } ]
        },
        { "id": "sheet-2", "title": "Sheet 2", "rootTopic": { "id": "r2", "title": "Ideas" } }]
        """

    private static let summaryTopic = #"""
        "summary": [ { "id": "sum", "title": "Done by Friday" } ]
        """#

    private var fullFile: Data {
        // The summary topic sits in Design's children next to the others.
        let json = Self.fullJSON.replacingOccurrences(
            of: #""callout": [ { "id": "c1", "title": "Ask Kim" } ] }"#,
            with: #""callout": [ { "id": "c1", "title": "Ask Kim" } ], "# + Self.summaryTopic + " }"
        )
        return ZipFixture.xmindJSON(json, extra: [("resources/pic.png", ZipFixture.png())])
    }

    // MARK: content.json

    @Test func eachSheetIsAMap() throws {
        let result = try read(fullFile)
        #expect(result.maps.map(\.map.title) == ["Launch", "Ideas"])
        #expect(result.maps[1].nodes.count == 1)
    }

    @Test func topicsKeepTheirTreeAndNotes() throws {
        let map = try read(fullFile).maps[0]
        #expect(map.outline == """
            Launch [Why we ship]
              Design
                Sketch
                Review
                Done by Friday
              Build
              Spec
            """)
        #expect(map.nodes.values.allSatisfy { $0.metadata.origin == .imported })
    }

    @Test func labelsBecomeTagsAndLinksStayLinks() throws {
        let map = try read(fullFile).maps[0]
        let design = try #require(map.firstNode(titled: "Design"))
        #expect(map.tags(of: design.id).map(\.name).sorted() == ["Q3", "UI"])
        #expect(design.link?.string == "https://example.com/design")
    }

    @Test func markersBecomePriorityAndTaskAndTheRestAreCounted() throws {
        let result = try read(fullFile)
        let design = try #require(result.maps[0].firstNode(titled: "Design"))
        #expect(design.priority == .high)
        #expect(design.taskState == .done)
        #expect(result.report.count(of: .icon) == 1)
    }

    @Test func aPlainCalloutBecomesTheTopicsCallout() throws {
        let map = try read(fullFile).maps[0]
        #expect(map.firstNode(titled: "Design")?.callout == "Ask Kim")
        #expect(map.firstNode(titled: "Ask Kim") == nil)
    }

    @Test func relationshipsAndTopicLinksBecomeConnections() throws {
        let result = try read(fullFile)
        let map = result.maps[0]
        let titles = map.edges.values.map { edge in
            [map.node(edge.sourceNodeID)!.title, map.node(edge.targetNodeID)!.title, edge.label ?? ""]
        }
        #expect(titles.sorted { $0[0] < $1[0] } == [["Build", "Design", ""], ["Spec", "Build", "feeds"]])
        // The second relationship names a topic the sheet does not have.
        #expect(result.report.count(of: .connection) == 1)
    }

    @Test func detachedTopicsFloatWhereTheyWere() throws {
        let map = try read(fullFile).maps[0]
        let floating = try #require(map.firstNode(titled: "Parking lot"))
        #expect(floating.isFloating(rootID: map.map.rootNodeID))
        #expect(floating.position == TopicPosition(x: -320, y: 180))
        #expect(map.children(of: floating.id).map(\.title) == ["Maybe later"])
    }

    @Test func summariesAndBoundariesCarryOver() throws {
        let map = try read(fullFile).maps[0]
        let design = try #require(map.firstNode(titled: "Design"))
        let build = try #require(map.firstNode(titled: "Build"))
        let summary = try #require(map.groups.values.first { $0.kind == .summary })
        #expect(summary.parentNodeID == design.id)
        #expect(map.node(summary.summaryNodeID!)?.title == "Done by Friday")
        #expect(map.node(summary.firstNodeID!)?.title == "Sketch")
        #expect(map.node(summary.lastNodeID!)?.title == "Review")

        let boundaries = map.groups.values.filter { $0.kind == .boundary }
        #expect(boundaries.count == 2)
        #expect(boundaries.contains { $0.title == "Week 1" && $0.parentNodeID == design.id })
        // "master" frames the topic itself, under its parent.
        #expect(boundaries.contains { $0.firstNodeID == build.id && $0.lastNodeID == build.id })
    }

    @Test func picturesBecomeTopicImagesWithTheirBytes() throws {
        let result = try read(fullFile)
        let map = result.maps[0]
        let design = try #require(map.firstNode(titled: "Design"))
        let image = try #require(map.image(of: design.id))
        #expect(image.data == nil)
        #expect(result.imageData[image.id]?.isEmpty == false)
        #expect(image.pixelWidth == 8)
        #expect(image.mapID == map.map.id)
    }

    @Test func attachmentsAreCounted() throws {
        let result = try read(fullFile)
        #expect(result.report.count(of: .attachment) == 1)
        #expect(result.report.count(of: .image) == 0)
        #expect(result.maps[0].firstNode(titled: "Spec")?.note == nil)
    }

    @Test func aMissingOrUnreadablePictureIsCountedAndTheTopicKept() throws {
        let json = #"""
            [{ "title": "S", "rootTopic": { "id": "r", "title": "Root", "children": { "attached": [
              { "id": "a", "title": "Gone", "image": { "src": "xap:resources/none.png" } },
              { "id": "b", "title": "Text", "image": { "src": "xap:resources/text.png" } } ] } } }]
            """#
        let result = try read(ZipFixture.xmindJSON(json, extra: [("resources/text.png", Data("not a picture".utf8))]))
        #expect(result.report.count(of: .image) == 2)
        #expect(result.maps[0].nodes.count == 3)
        #expect(result.maps[0].images.isEmpty)
    }

    @Test func aSummaryThatCannotBracketKeepsItsTopic() throws {
        let json = #"""
            [{ "title": "S", "rootTopic": { "id": "r", "title": "Root",
              "children": { "attached": [ { "id": "a", "title": "A" } ],
                            "summary": [ { "id": "s", "title": "Sum", "children": { "attached": [ { "id": "s1", "title": "Under" } ] } } ] },
              "summaries": [ { "range": "(0,4)", "topicId": "s" } ],
              "boundaries": [ { "range": "master" }, { "range": "(3,9)" } ] } }]
            """#
        let result = try read(ZipFixture.xmindJSON(json))
        #expect(result.maps[0].outline == """
            Root
              A
              Sum
                Under
            """)
        #expect(result.maps[0].groups.isEmpty)
        #expect(result.report.count(of: .summary) == 1)
        // A boundary around the central topic, and one past the last child.
        #expect(result.report.count(of: .boundary) == 2)
    }

    @Test func labelsTooLongForATagAndOtherLinksGoToTheNote() throws {
        let long = String(repeating: "x", count: 50)
        let json = """
            [{ "title": "S", "rootTopic": { "id": "r", "title": "Root", "labels": ["\(long)"],
               "href": "file:///Users/kim/plan.txt", "notes": { "plain": { "content": "Note" } } } }]
            """
        let map = try read(ZipFixture.xmindJSON(json)).maps[0]
        #expect(map.root?.note == "Note\n\n\(long)\n\nfile:///Users/kim/plan.txt")
        #expect(map.tags.isEmpty)
        #expect(map.root?.link == nil)
    }

    @Test func storedEntriesReadToo() throws {
        let json = #"[{ "title": "S", "rootTopic": { "id": "r", "title": "Stored" } }]"#
        let data = ZipFixture([("content.json", Data(json.utf8))], deflate: false).data
        #expect(try read(data).maps[0].map.title == "Stored")
    }

    @Test func theJSONWinsOverTheWarningXML() throws {
        let json = #"[{ "title": "S", "rootTopic": { "id": "r", "title": "Real" } }]"#
        let xml = #"<xmap-content><sheet><topic><title>Warning: update XMind</title></topic></sheet></xmap-content>"#
        let data = ZipFixture([("content.xml", Data(xml.utf8)), ("content.json", Data(json.utf8))]).data
        #expect(try read(data).maps.map(\.map.title) == ["Real"])
    }

    @Test func anUntitledRootTakesTheSheetsTitle() throws {
        let json = #"[{ "title": "Sheet A", "rootTopic": { "id": "r", "title": "" } }]"#
        #expect(try read(ZipFixture.xmindJSON(json)).maps[0].map.title == "Sheet A")
    }

    // MARK: content.xml (XMind 8)

    private static let xml8 = """
        <?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <xmap-content xmlns="urn:xmind:xmap:xmlns:content:2.0" xmlns:fo="http://www.w3.org/1999/XSL/Format"
            xmlns:svg="http://www.w3.org/2000/svg" xmlns:xhtml="http://www.w3.org/1999/xhtml"
            xmlns:xlink="http://www.w3.org/1999/xlink" version="2.0">
          <sheet id="s1" timestamp="1">
            <topic id="root" structure-class="org.xmind.ui.map.unbalanced" timestamp="1">
              <title>Trip</title>
              <notes><plain>Pack light</plain><html><xhtml:p>Pack light</xhtml:p></html></notes>
              <children>
                <topics type="attached">
                  <topic id="t1" xlink:href="https://example.com/flights">
                    <title>Flights</title>
                    <labels><label>booked, paid</label></labels>
                    <marker-refs><marker-ref marker-id="priority-2"/><marker-ref marker-id="smiley-laugh"/></marker-refs>
                    <xhtml:img xhtml:src="xap:attachments/map.png" svg:width="40"/>
                  </topic>
                  <topic id="t2" xlink:href="xmind:#t1">
                    <title>Hotel</title>
                    <children>
                      <topics type="attached">
                        <topic id="t21"><title>Night 1</title></topic>
                        <topic id="t22"><title>Night 2</title></topic>
                      </topics>
                      <topics type="summary">
                        <topic id="sum"><title>Two nights</title></topic>
                      </topics>
                    </children>
                    <boundaries><boundary id="b1" range="(0,1)"><title>Kyoto</title></boundary></boundaries>
                    <summaries><summary id="x" range="(0,1)" topic-id="sum"/></summaries>
                  </topic>
                </topics>
                <topics type="detached">
                  <topic id="d1"><title>Souvenirs</title><position svg:x="200" svg:y="-150"/></topic>
                </topics>
              </children>
            </topic>
            <title>Sheet 1</title>
            <relationships>
              <relationship end1="d1" end2="t21" id="r1"><title>buy here</title></relationship>
            </relationships>
          </sheet>
          <sheet id="s2"><topic id="r2"><title>Budget</title></topic><title>Sheet 2</title></sheet>
        </xmap-content>
        """

    @Test func xmind8SheetsTopicsAndNotes() throws {
        let result = try read(ZipFixture.xmindXML(Self.xml8, extra: [("attachments/map.png", ZipFixture.png())]))
        #expect(result.maps.map(\.map.title) == ["Trip", "Budget"])
        let map = result.maps[0]
        #expect(map.outline == """
            Trip [Pack light]
              Flights
              Hotel
                Night 1
                Night 2
                Two nights
            """)
    }

    @Test func xmind8TopicFields() throws {
        let result = try read(ZipFixture.xmindXML(Self.xml8, extra: [("attachments/map.png", ZipFixture.png())]))
        let map = result.maps[0]
        let flights = try #require(map.firstNode(titled: "Flights"))
        #expect(flights.link?.string == "https://example.com/flights")
        #expect(map.tags(of: flights.id).map(\.name).sorted() == ["booked", "paid"])
        #expect(flights.priority == .medium)
        #expect(map.image(of: flights.id) != nil)
        #expect(result.report.count(of: .icon) == 1)

        let floating = try #require(map.firstNode(titled: "Souvenirs"))
        #expect(floating.position == TopicPosition(x: 200, y: -150))
        #expect(map.groups.values.contains { $0.kind == .boundary && $0.title == "Kyoto" })
        #expect(map.groups.values.contains { $0.kind == .summary && map.node($0.summaryNodeID!)?.title == "Two nights" })

        let labels = map.edges.values.map { edge in
            "\(map.node(edge.sourceNodeID)!.title)→\(map.node(edge.targetNodeID)!.title) \(edge.label ?? "")"
        }
        #expect(Set(labels) == ["Souvenirs→Night 1 buy here", "Hotel→Flights "])
        #expect(result.report.isEmpty == false)
    }

    @Test func xmind8DeepNestingStreams() throws {
        var xml = "<xmap-content><sheet><topic><title>0</title>"
        for level in 1 ... 2_000 {
            xml += "<children><topics type=\"attached\"><topic><title>\(level)</title>"
        }
        xml += String(repeating: "</topic></topics></children>", count: 2_000)
        xml += "</topic></sheet></xmap-content>"
        let map = try read(ZipFixture.xmindXML(xml)).maps[0]
        #expect(map.nodes.count == 2_001)
    }

    // MARK: Damaged files

    @Test func notAZipIsTheWrongFormat() {
        #expect(readError(Data("<xmap-content/>".utf8)) == .wrongFormat)
        #expect(readError(Data()) == .wrongFormat)
    }

    @Test func aZipWithoutContentIsTheWrongFormat() {
        #expect(readError(ZipFixture([("readme.txt", Data("hi".utf8))]).data) == .wrongFormat)
    }

    @Test func anotherXMLRootIsTheWrongFormat() {
        #expect(readError(ZipFixture.xmindXML("<opml version=\"2.0\"><body/></opml>")) == .wrongFormat)
    }

    @Test func brokenContentIsDamaged() {
        #expect(readError(ZipFixture.xmindJSON("[{ \"rootTopic\": ")) == .damaged)
        #expect(readError(ZipFixture.xmindXML("<xmap-content><sheet><topic>")) == .damaged)
    }

    @Test func aTruncatedArchiveIsDamagedOrNotAnArchive() {
        let data = fullFile
        // Cut inside the central directory: the end record is gone.
        #expect(readError(data.prefix(data.count - 30)) == .wrongFormat)
        // Cut inside the entries: the end record points past them.
        var cut = data
        cut.removeSubrange(10 ..< 200)
        #expect(readError(cut) == .damaged)
    }

    @Test func aWrongChecksumIsDamaged() {
        var zip = ZipFixture([("content.json", Data(#"[{"rootTopic":{"title":"A"}}]"#.utf8))])
        zip.files[0].crc = 1234
        #expect(readError(zip.data) == .damaged)
    }

    @Test func anEntryThatExpandsPastItsDeclaredSizeIsDamaged() {
        var zip = ZipFixture([("content.json", Data(#"[{"rootTopic":{"title":"Aaaaaaaaaaaaaaaaaaaaaaaaaa"}}]"#.utf8))])
        zip.files[0].declaredSize = 10
        #expect(readError(zip.data) == .damaged)
    }

    @Test func aZipBombIsRefusedBeforeItIsInflated() {
        // 4 MB of zeros deflates to a few kilobytes.
        let zeros = Data(count: 4 * 1_024 * 1_024)
        let bomb = ZipFixture([("content.json", zeros)]).data
        #expect(bomb.count < 64 * 1_024)
        let limits = XMindMap.ZipLimits(maximumEntrySize: 1_024 * 1_024, maximumTotalSize: 2 * 1_024 * 1_024)
        #expect(readError(bomb, limits: limits) == .tooLarge)
    }

    @Test func picturesCountTowardsTheTotalLimit() throws {
        let json = #"[{ "title": "S", "rootTopic": { "id": "r", "title": "R", "image": { "src": "xap:resources/big.bin" } } }]"#
        let data = ZipFixture.xmindJSON(json, extra: [("resources/big.bin", Data(count: 600_000))])
        let limits = XMindMap.ZipLimits(maximumEntrySize: 1_000_000, maximumTotalSize: 500_000)
        // The picture is over the limit: it is counted and the map still reads.
        let result = try read(data, limits: limits)
        #expect(result.report.count(of: .image) == 1)
        #expect(result.maps[0].nodes.count == 1)
    }

    @Test func noSheetsIsEmpty() {
        #expect(readError(ZipFixture.xmindJSON("[]")) == .emptyDocument)
        #expect(readError(ZipFixture.xmindJSON(#"[{ "title": "No root" }]"#)) == .emptyDocument)
        #expect(readError(ZipFixture.xmindXML("<xmap-content/>")) == .emptyDocument)
    }

    @Test func theFormatIsPickedByExtension() async throws {
        #expect(ForeignFormat(fileExtension: "XMind") == .xmind)
        let result = try await ForeignFormat.xmind.read(fullFile, fileName: "Plans")
        #expect(result.maps.count == 2)
    }
}

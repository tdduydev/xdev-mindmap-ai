import Foundation
import MindMapDomain
import MindMapGraph
import Testing
@testable import MindMapInterchange

/// Fixtures are written for these tests in the shape FreeMind 1.0 saves
/// (its schema `freemind.xsd`) and Freeplane 1.x saves (the file format page
/// of the Freeplane wiki and docs.freeplane.org); no file from either app is
/// copied, since none came with a licence to ship it.
@Suite struct FreeMindMapTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func read(_ xml: String, fileName: String = "File") async throws -> ForeignImport {
        try await ForeignFormat.freeMind.read(Data(xml.utf8), fileName: fileName, now: now)
    }

    private static let freeMind10 = """
        <map version="1.0.1">
        <!-- To view this file, download free mind mapping software FreeMind from http://freemind.sourceforge.net -->
        <node CREATED="1696300000000" ID="ID_1000" MODIFIED="1696300000000" TEXT="Launch">
        <node CREATED="1696300000000" FOLDED="true" ID="ID_1001" MODIFIED="1696300000000" POSITION="right" TEXT="Marketing" COLOR="#990000">
        <edge COLOR="#0033ff" STYLE="bezier" WIDTH="thin"/>
        <font NAME="SansSerif" SIZE="12" BOLD="true"/>
        <icon BUILTIN="idea"/>
        <icon BUILTIN="yes"/>
        <arrowlink DESTINATION="ID_1003" ENDARROW="Default" ENDINCLINATION="40;0;" ID="Arrow_ID_1" STARTARROW="None" STARTINCLINATION="40;0;"/>
        <node CREATED="1696300000000" ID="ID_1002" MODIFIED="1696300000000" TEXT="Press kit" LINK="https://example.com/press">
        <richcontent TYPE="NOTE"><html>
          <head>
            <style>p { margin-top: 0 }</style>
          </head>
          <body>
            <p>
              Send to&#160;editors
            </p>
            <p>
              by <b>Friday</b>
            </p>
          </body>
        </html></richcontent>
        </node>
        </node>
        <node CREATED="1696300000000" ID="ID_1003" MODIFIED="1696300000000" POSITION="left" BACKGROUND_COLOR="#00cc66">
        <richcontent TYPE="NODE"><html>
          <head></head>
          <body>
            <p>Sales</p>
            <p><img src="chart.png"/>Q4 plan</p>
          </body>
        </html></richcontent>
        <node CREATED="1696300000000" ID="ID_1004" MODIFIED="1696300000000" TEXT="See marketing" LINK="#ID_1001"/>
        <node CREATED="1696300000000" ID="ID_1005" MODIFIED="1696300000000" TEXT="Brief" LINK="file:/Users/me/brief.pdf" COLOR="#000000"/>
        </node>
        </node>
        </map>
        """

    private static let freeplane1 = """
        <map version="freeplane 1.9.13">
        <!--To view this file, download free mind mapping software Freeplane from https://www.freeplane.org -->
        <attribute_registry SHOW_ATTRIBUTES="hide"/>
        <node TEXT="Trip" FOLDED="false" ID="ID_696401721" CREATED="1610381621824" MODIFIED="1696300000000" STYLE="oval">
        <font SIZE="18"/>
        <hook NAME="MapStyle">
            <map_styles>
                <stylenode LOCALIZED_TEXT="styles.root_node" STYLE="oval">
                    <stylenode LOCALIZED_TEXT="default" ICON_SIZE="12 pt" COLOR="#000000"/>
                </stylenode>
            </map_styles>
        </hook>
        <hook NAME="AutomaticEdgeColor" COUNTER="2" RULE="ON_BRANCH_CREATION"/>
        <node TEXT="Packing" POSITION="right" ID="ID_1" CREATED="1696300000000" MODIFIED="1696300000000" FOLDED="true">
        <edge COLOR="#ff00ff"/>
        <richcontent TYPE="DETAILS" CONTENT-TYPE="xml/">
        <html><head></head><body><p>Carry-on only</p></body></html>
        </richcontent>
        <richcontent TYPE="NOTE" CONTENT-TYPE="plain/markdown"><text>- passport
        - charger</text></richcontent>
        <attribute NAME="weight" VALUE="7 kg"/>
        <hook URI="bag.png" SIZE="1.0" NAME="ExternalObject"/>
        <node TEXT="Clothes" ID="ID_2" CREATED="1696300000000" MODIFIED="1696300000000">
        <edge COLOR="#ff00ff"/>
        </node>
        </node>
        <node TEXT="Route" POSITION="left" ID="ID_3" CREATED="1696300000000" MODIFIED="1696300000000">
        <edge COLOR="#00ffff"/>
        <arrowlink SHAPE="CUBIC_CURVE" COLOR="#ff0000" WIDTH="2" TRANSPARENCY="200" DASH="" FONT_SIZE="9" FONT_FAMILY="SansSerif" DESTINATION="ID_1" MIDDLE_LABEL="needs" STARTINCLINATION="1;2;" ENDINCLINATION="3;4;" STARTARROW="DEFAULT" ENDARROW="DEFAULT"/>
        <arrowlink DESTINATION="ID_404"/>
        <cloud COLOR="#f0f0f0" SHAPE="ARC"/>
        </node>
        </node>
        </map>
        """

    @Test func readsAFreeMind10Map() async throws {
        let result = try await read(Self.freeMind10)
        let map = try #require(result.maps.first)
        #expect(result.maps.count == 1)
        #expect(map.map.title == "Launch")
        #expect(map.outline == """
            Launch
              Marketing
                Press kit [Send to editors
            by Friday]
              Sales
            Q4 plan
                See marketing
                Brief [file:/Users/me/brief.pdf]
            """)

        let marketing = try #require(map.firstNode(titled: "Marketing"))
        // The branch's edge colour wins over the text colour.
        #expect(marketing.color == .blue)
        #expect(marketing.isCollapsed)
        #expect(map.firstNode(titled: "Press kit")?.color == nil, "inherits the branch colour")
        #expect(map.firstNode(titled: "Press kit")?.link?.string == "https://example.com/press")
        let sales = try #require(map.firstNode(titled: "Sales\nQ4 plan"))
        #expect(sales.color == .green)
        #expect(map.firstNode(titled: "Brief")?.color == nil, "black text keeps the branch colour")
        #expect(map.firstNode(titled: "Brief")?.link == nil)
        #expect(map.nodes.values.allSatisfy { $0.metadata.origin == .imported })

        // The arrowlink and the `#ID` link are both Connections.
        let see = try #require(map.firstNode(titled: "See marketing"))
        let pairs = Set(map.edges.values.map { [$0.sourceNodeID, $0.targetNodeID] })
        #expect(pairs == [[marketing.id, sales.id], [see.id, marketing.id]])
        #expect(map.edges.values.allSatisfy { $0.arrowHeads == .end })

        #expect(result.report.count(of: .icon) == 2)
        #expect(result.report.count(of: .image) == 1)
        #expect(result.report.entries.map(\.loss) == [.image, .icon])
    }

    @Test func readsAFreeplane1Map() async throws {
        let result = try await read(Self.freeplane1)
        let map = try #require(result.maps.first)
        // Map styles in the hook are not topics; attributes and clouds are skipped.
        #expect(map.outline == """
            Trip
              Packing [Carry-on only

            - passport
            - charger]
                Clothes
              Route
            """)
        let packing = try #require(map.firstNode(titled: "Packing"))
        #expect(packing.color == .violet)
        #expect(packing.isCollapsed)
        #expect(map.firstNode(titled: "Clothes")?.color == nil, "same colour as its parent")
        #expect(map.firstNode(titled: "Route")?.color == .teal)
        #expect(map.firstNode(titled: "Trip")?.isCollapsed == false)

        let edge = try #require(map.edges.values.first)
        #expect(map.edges.count == 1, "a link to a missing node is dropped")
        #expect(edge.sourceNodeID == map.firstNode(titled: "Route")?.id)
        #expect(edge.targetNodeID == packing.id)
        #expect(edge.label == "needs")
        #expect(edge.arrowHeads == .both)
        #expect(edge.color == .rose)

        #expect(result.report.count(of: .image) == 1)
        #expect(result.report.count(of: .icon) == 0)
    }

    @Test func mapsColoursToThePaletteByHue() {
        #expect(FreeMindMap.paletteColor("#ff0000") == .rose)
        #expect(FreeMindMap.paletteColor("#ff9900") == .amber)
        #expect(FreeMindMap.paletteColor("#ffff00") == .amber)
        #expect(FreeMindMap.paletteColor("#00cc00") == .green)
        #expect(FreeMindMap.paletteColor("#00cccc") == .teal)
        #expect(FreeMindMap.paletteColor("#0000ff") == .blue)
        #expect(FreeMindMap.paletteColor("#9900ff") == .violet)
        #expect(FreeMindMap.paletteColor("#ff3399") == .rose)
        // Greys, black and white have no palette colour.
        #expect(FreeMindMap.paletteColor("#000000") == nil)
        #expect(FreeMindMap.paletteColor("#ffffff") == nil)
        #expect(FreeMindMap.paletteColor("#808080") == nil)
        #expect(FreeMindMap.paletteColor("#111a11") == nil)
        #expect(FreeMindMap.paletteColor("red") == nil)
        #expect(FreeMindMap.paletteColor(nil) == nil)
    }

    @Test func refusesFilesThatAreNotMaps() async {
        await #expect(throws: ForeignImportError.wrongFormat) {
            try await read(#"<opml version="2.0"><body/></opml>"#)
        }
        await #expect(throws: ForeignImportError.damaged) {
            try await read(#"<map version="1.0.1"><node TEXT="A">"#)
        }
        await #expect(throws: ForeignImportError.damaged) {
            try await read("not xml")
        }
        await #expect(throws: ForeignImportError.emptyDocument) {
            try await read(#"<map version="1.0.1"></map>"#)
        }
    }

    @Test func readsTheExtension() {
        #expect(ForeignFormat(fileExtension: "mm") == .freeMind)
        #expect(ForeignFormat(fileExtension: "MM") == .freeMind)
        #expect(ForeignFormat.freeMind.fileExtension == "mm")
    }

    @Test func keepsEveryTopicOfADeepMap() async throws {
        let depth = 2_000
        let xml = #"<map version="1.0.1">"#
            + (0..<depth).map { #"<node TEXT="T\#($0)" FOLDED="true">"# }.joined()
            + String(repeating: "</node>", count: depth)
            + "</map>"
        let map = try #require(try await read(xml).maps.first)
        #expect(map.nodes.count == depth)
        #expect(map.nodes.values.count(where: \.isCollapsed) == depth - 2, "not the root, not the leaf")
    }

    @Test func severalTopLevelNodesGoUnderTheFileName() async throws {
        let map = try #require(try await read("""
            <map version="1.0.1"><node TEXT="A" ID="a"/><node TEXT="B" ID="b"><arrowlink DESTINATION="a"/></node></map>
            """, fileName: "Notes").maps.first)
        #expect(map.outline == "Notes\n  A\n  B")
        #expect(map.edges.values.first?.sourceNodeID == map.firstNode(titled: "B")?.id)
        #expect(map.edges.values.first?.targetNodeID == map.firstNode(titled: "A")?.id)
    }
}

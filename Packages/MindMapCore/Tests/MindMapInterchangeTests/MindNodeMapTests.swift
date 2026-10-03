import Foundation
import MindMapDomain
import MindMapGraph
import Testing
@testable import MindMapInterchange

/// The fixture is a binary property list in the shape of MindNode's
/// `contents.xml` (`version` 6 and 7, see `MindNodeMap`), written for the test.
@Suite struct MindNodeMapTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private static func node(_ id: String, _ html: String, color: String? = nil, extra: [String: Any] = [:], _ subnodes: [[String: Any]] = []) -> [String: Any] {
        var node: [String: Any] = [
            "nodeID": id,
            "location": "{0, 0}",
            "hasFoldedSubnodes": false,
            "title": ["allowToShrinkWidth": true, "maxWidth": 300, "text": html],
            "subnodes": subnodes,
        ]
        if let color { node["pathStyle"] = ["strokeStyle": ["color": color, "width": 6, "dash": 0]] }
        return node.merging(extra) { $1 }
    }

    private static func contents(_ mainNodes: [[String: Any]], canvas extra: [String: Any] = [:]) throws -> Data {
        let canvas: [String: Any] = ["color": "{0.93, 0.93, 0.95, 1.0}", "mindMaps": mainNodes.map { ["mainNode": $0, "layoutStyle": 2] }]
        let root: [String: Any] = ["version": 6, "typeOptions": 0, "canvas": canvas.merging(extra) { $1 }]
        return try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
    }

    private static let paragraph = "<p style='color: rgba(90, 89, 89, 1.000000); font: 20px \"Helvetica\"; -cocoa-font-postscriptname: \"Helvetica\"; '>"

    @Test func readsTheTreeNotesColoursAndConnections() async throws {
        let data = try Self.contents([
            Self.node("R", Self.paragraph + "Automated Script</p>", color: "{0.294118, 0.294118, 0.294118, 1.000000}", [
                Self.node("A", Self.paragraph + "Shell &amp; tools</p>", color: "{0.464310, 0.078533, 0.566906, 1.000000}", extra: [
                    "hasFoldedSubnodes": true,
                    "note": ["visibleOnCanvas": false, "text": "<p><span style='font: 15px'>Line one</span></p><p>if a &lt; b</p>"],
                ], [Self.node("A1", Self.paragraph + "Stop on error</p>")]),
                Self.node("B", "<p>Library</p>", extra: ["task": ["state": 1, "uuids": [String: Any]()]]),
            ]),
        ], canvas: [
            "crossConnections": [[
                "connectionID": "C1",
                "title": ["text": "<p style='text-align: center'>uses</p>"],
                "arrowStyle": ["startArrow": 0, "endArrow": 1],
                "endPoints": ["startNodeID": "A1", "endNodeID": "B"],
            ], [
                "endPoints": ["startNodeID": "A1", "endNodeID": "missing"],
            ]],
            "boundaries": [["nodeID": "A"]],
        ])
        let imported = try await MindNodeMap.read(contents: data, fileName: "File", now: now)
        let map = try #require(imported.maps.first)
        #expect(map.outline == """
            Automated Script
              Shell & tools [Line one
            if a < b]
                Stop on error
              Library
            """)
        let shell = try #require(map.firstNode(titled: "Shell & tools"))
        #expect(shell.color == .violet)
        #expect(shell.isCollapsed)
        #expect(map.firstNode(titled: "Automated Script")?.color == nil, "grey is no colour")
        #expect(map.firstNode(titled: "Library")?.taskState == .open)
        #expect(map.edges.count == 1)
        let edge = try #require(map.edges.values.first)
        #expect(edge.label == "uses")
        #expect(edge.arrowHeads == .end)
        #expect(edge.targetNodeID == map.firstNode(titled: "Library")?.id)
        #expect(imported.report.count(of: .boundary) == 1)
    }

    @Test func severalMapsOnTheCanvasGoUnderACentralTopicNamedByTheFile() async throws {
        let data = try Self.contents([Self.node("A", "<p>One</p>"), Self.node("B", "<p>Two</p>")])
        let imported = try await MindNodeMap.read(contents: data, fileName: "Canvas", now: now)
        #expect(imported.maps.first?.outline == "Canvas\n  One\n  Two")
    }

    @Test func refusesOtherFiles() async throws {
        await #expect(throws: ForeignImportError.wrongFormat) {
            try await MindNodeMap.read(contents: Data("<html/>".utf8), fileName: "File", now: now)
        }
        let other = try PropertyListSerialization.data(fromPropertyList: ["canvas": [String: Any]()], format: .xml, options: 0)
        await #expect(throws: ForeignImportError.wrongFormat) {
            try await MindNodeMap.read(contents: other, fileName: "File", now: now)
        }
        await #expect(throws: ForeignImportError.emptyDocument) {
            try await MindNodeMap.read(contents: try Self.contents([]), fileName: "File", now: now)
        }
    }

    @Test func htmlBecomesPlainLines() {
        #expect(MindNodeMap.plainText("Plain") == "Plain")
        #expect(MindNodeMap.plainText("<p>a<br>b</p><p>  c   d </p>") == "a\nb\nc d")
        #expect(MindNodeMap.plainText("<p>&#26085;&#x672C; &unknown; R&D</p>") == "日本 &unknown; R&D")
    }
}

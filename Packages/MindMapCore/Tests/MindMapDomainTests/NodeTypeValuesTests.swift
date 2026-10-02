import Foundation
import MindMapDomain
import Testing

@Suite("Node type values")
struct NodeTypeValuesTests {
    @Test func linksAreNormalisedAndLimitedToWebAndMail() throws {
        #expect(TopicLink.normalized("  Example.COM/Path?q=1 ")?.string == "https://example.com/Path?q=1")
        #expect(TopicLink.normalized("HTTP://Example.com")?.string == "http://example.com")
        #expect(TopicLink.normalized("mailto:team@example.com")?.string == "mailto:team@example.com")
        #expect(TopicLink.normalized("ftp://example.com") == nil)
        #expect(TopicLink.normalized("javascript:alert(1)") == nil)
        #expect(TopicLink.normalized("two words") == nil)
        #expect(TopicLink.normalized("   ") == nil)
        #expect(TopicLink.normalized("https://" + String(repeating: "a", count: TopicLink.maximumLength)) == nil)
    }

    /// A link this build cannot open is still kept as text.
    @Test func storedLinkKeepsTextItCannotOpen() {
        let link = TopicLink(string: "obsidian://open?vault=x")
        #expect(link.url == nil)
        #expect(link.string == "obsidian://open?vault=x")
        #expect(TopicLink(string: "https://example.com").url?.host == "example.com")
    }

    @Test func positionsAreAlwaysDrawable() {
        #expect(TopicPosition(x: .nan, y: .infinity) == TopicPosition(x: 0, y: 0))
        #expect(TopicPosition(x: 1e9, y: -1e9) == TopicPosition(x: TopicPosition.limit, y: -TopicPosition.limit))
        #expect(TopicPosition(x: 12.5, y: -40) == TopicPosition(x: 12.5, y: -40))
    }

    @Test func calloutAndAltTextAreTrimmedAndCapped() {
        #expect(MindNode.normalizedCallout("  Check budget \n") == "Check budget")
        #expect(MindNode.normalizedCallout(" \n ") == nil)
        #expect(MindNode.normalizedCallout(String(repeating: "x", count: 400))?.count == MindNode.maximumCalloutLength)
        #expect(MindImage.normalizedAltText(String(repeating: "y", count: 300))?.count == MindImage.maximumAltTextLength)
        #expect(MindImage.normalizedAltText("  ") == nil)
    }

    /// A node type from a newer build round-trips instead of becoming `topic`.
    @Test func unknownNodeTypeSurvivesCoding() throws {
        let mapID = MapID()
        let node = MindNode(mapID: mapID, parentID: nil, title: "Card", nodeType: NodeType(rawValue: "kanbanCard"))
        let decoded = try JSONDecoder().decode(MindNode.self, from: JSONEncoder().encode(node))
        #expect(decoded.nodeType.rawValue == "kanbanCard")
        #expect(decoded == node)
    }

    @Test func floatingIsParentlessNotRootWithPosition() {
        let mapID = MapID()
        let root = MindNode(mapID: mapID, parentID: nil, title: "Root", position: TopicPosition(x: 1, y: 1))
        #expect(!root.isFloating(rootID: root.id))
        #expect(root.isFloating(rootID: NodeID()))
        #expect(!MindNode(mapID: mapID, parentID: NodeID(), title: "A", position: TopicPosition(x: 1, y: 1)).isFloating(rootID: nil))
        #expect(!MindNode(mapID: mapID, parentID: nil, title: "B").isFloating(rootID: root.id))
    }
}

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

    @Test func typedLinksGetASchemeAndEncoding() throws {
        #expect(try TopicLink.validated("name@example.com")?.string == "mailto:name@example.com")
        #expect(try TopicLink.validated("example.com:8080/a")?.string == "https://example.com:8080/a")
        #expect(try TopicLink.validated("https://example.com/a b")?.string == "https://example.com/a%20b")
        #expect(try TopicLink.validated("https://vi.wikipedia.org/wiki/Hà_Nội")?.url != nil)
        #expect(try TopicLink.validated(" \n ") == nil)
    }

    @Test func refusedLinksSayWhy() {
        #expect(throws: TopicLinkError.unsupportedScheme) { try TopicLink.validated("file:///etc/hosts") }
        #expect(throws: TopicLinkError.unsupportedScheme) { try TopicLink.validated("javascript:alert(1)") }
        #expect(throws: TopicLinkError.unsupportedScheme) { try TopicLink.validated("data:text/html,hi") }
        #expect(throws: TopicLinkError.missingHost) { try TopicLink.validated("https://") }
        #expect(throws: TopicLinkError.missingAddress) { try TopicLink.validated("mailto:") }
        #expect(throws: TopicLinkError.tooLong) {
            try TopicLink.validated("https://example.com/" + String(repeating: "a", count: TopicLink.maximumLength))
        }
    }

    @Test func linksAreNamedByHostOrAddress() {
        #expect(TopicLink(string: "https://example.com/private?token=1").displayName == "example.com")
        #expect(TopicLink(string: "mailto:team@example.com").displayName == "team@example.com")
        #expect(TopicLink(string: "mailto:team@example.com").isMail)
        #expect(TopicLink(string: "obsidian://x").displayName == nil)
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

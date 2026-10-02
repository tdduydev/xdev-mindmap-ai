import Foundation
import MindMapAICore
import MindMapDomain
import MindMapGraph
import MindMapTestSupport
import Testing

/// A floating topic is a topic without ancestors (FR-ORG-27, docs/node-organization.md).
@Suite("AI context around floating topics")
struct FloatingContextTests {
    let floatingID = NodeID()
    let childID = NodeID()
    let fixture: OutlineFixture

    init() throws {
        var fixture = try OutlineFixture("""
        Launch
          Marketing
          Product
        """, mapTitle: "Launch plan")
        try fixture.engine.execute(AddFloatingTopicCommand(nodeID: floatingID, title: "Parking lot", position: TopicPosition(x: 0, y: 400)))
        try fixture.engine.execute(AddNodeCommand(nodeID: childID, .child(of: floatingID), title: "Podcast"))
        self.fixture = fixture
    }

    private func context(for id: NodeID) throws -> AIContext {
        try AIContextBuilder().context(for: id, in: fixture.state, language: .english, userLocaleIdentifier: "en_US")
    }

    @Test func floatingFocusHasNoAncestorsOrSiblings() throws {
        let context = try context(for: floatingID)
        #expect(context.mapTitle == "Launch plan")
        #expect(context.focus.title == "Parking lot")
        #expect(context.ancestors.isEmpty)
        #expect(context.siblings.isEmpty)
        #expect(context.descendants.map(\.title) == ["Podcast"])
    }

    /// The path of a topic in a floating branch stops at the floating topic,
    /// never at the central topic.
    @Test func floatingBranchPathStopsAtTheFloatingTopic() throws {
        let context = try context(for: childID)
        #expect(context.ancestors.map(\.title) == ["Parking lot"])
        #expect(context.siblings.isEmpty)
    }

    /// The central topic's branch is the main tree only.
    @Test func centralTopicContextLeavesFloatingBranchesOut() throws {
        let context = try context(for: fixture["Launch"])
        #expect(context.descendants.map(\.title) == ["Marketing", "Product"])
        #expect(context.omittedDescendantCount == 0)
    }
}

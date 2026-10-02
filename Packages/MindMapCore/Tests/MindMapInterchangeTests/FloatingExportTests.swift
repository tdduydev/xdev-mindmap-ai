import Foundation
import MindMapDomain
import MindMapGraph
@testable import MindMapInterchange
import Testing

/// Markdown and plain text write the main tree, then each floating branch as a
/// further top-level item (FR-ORG-27).
@Suite("Exporting floating topics")
struct FloatingExportTests {
    static func state() throws -> GraphState {
        var engine = try GraphEngine(state: GraphState(map: MindMap(title: "Plan")))
        let root = NodeID()
        let first = NodeID()
        try engine.execute(AddNodeCommand(nodeID: root, .root, title: "Plan"))
        try engine.execute(AddNodeCommand(.child(of: root), title: "Goals"))
        try engine.execute(AddFloatingTopicCommand(nodeID: first, title: "Parking lot", position: TopicPosition(x: 0, y: 400)))
        try engine.execute(AddNodeCommand(.child(of: first), title: "Podcast", note: "Maybe in Q3"))
        try engine.execute(AddFloatingTopicCommand(title: "Aside", position: TopicPosition(x: -300, y: 0)))
        return engine.state
    }

    @Test func markdownPutsFloatingBranchesAfterTheMainTree() throws {
        let markdown = try MarkdownOutline.export(Self.state())
        #expect(markdown == """
        # Plan

        ## Goals

        # Parking lot

        ## Podcast

        Maybe in Q3

        # Aside

        """)
        // Read back, several top-level items become main topics (MM-10a rule).
        let draft = MarkdownOutline.parse(markdown)
        #expect(draft.outline == """
        Plan
          Goals
        Parking lot
          Podcast [Maybe in Q3]
        Aside
        """)
    }

    @Test func plainTextPutsFloatingBranchesAfterTheMainTree() throws {
        let text = try PlainTextOutline.export(Self.state(), includeNotes: false)
        #expect(PlainTextOutline.parse(text).outline == """
        Plan
          Goals
        Parking lot
          Podcast
        Aside
        """)
    }

    @Test func exportingABranchStaysInsideIt() throws {
        let state = try Self.state()
        let floating = try #require(state.floatingTopicIDs.first)
        #expect(try MarkdownOutline.export(state, branch: floating, options: .init(includeNotes: false)) == "# Parking lot\n\n## Podcast\n")
        let root = try #require(state.map.rootNodeID)
        #expect(try MarkdownOutline.export(state, branch: root) == "# Plan\n\n## Goals\n")
    }
}

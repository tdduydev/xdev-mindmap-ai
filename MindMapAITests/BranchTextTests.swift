import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import Testing

/// The clipboard text of FR-EDT-14, until MindMapInterchange (MM-10a) takes over.
@Suite("Branch text")
struct BranchTextTests {
    private typealias Item = BranchText.Item

    @Test func plainIndentedLinesNest() {
        let items = BranchText.outline(from: "Plan\n  Research\n    Interviews\n  Design\nShip")

        #expect(items == [
            Item(depth: 0, title: "Plan"),
            Item(depth: 1, title: "Research"),
            Item(depth: 2, title: "Interviews"),
            Item(depth: 1, title: "Design"),
            Item(depth: 0, title: "Ship"),
        ])
    }

    @Test func markdownListsHeadingsAndTasksNest() {
        let text = """
        # Launch
        ## Press
        - [ ] Release
          1. Draft
          2) Review
        * Social
        """

        #expect(BranchText.outline(from: text) == [
            Item(depth: 0, title: "Launch"),
            Item(depth: 1, title: "Press"),
            Item(depth: 2, title: "Release"),
            Item(depth: 3, title: "Draft"),
            Item(depth: 3, title: "Review"),
            Item(depth: 2, title: "Social"),
        ])
    }

    @Test func tooDeepIndentationIsClamped() {
        let items = BranchText.outline(from: "\t\t\tDeep\nTop\n\t\t\tUnder top")

        #expect(items.map(\.depth) == [0, 0, 1])
    }

    @Test func quoteLinesAreTheNoteOfTheTopicAbove() {
        let items = BranchText.outline(from: "- Plan\n  > First line\n  >\n  > Third line\n- Next")

        #expect(items == [Item(depth: 0, title: "Plan", note: "First line\n\nThird line"), Item(depth: 0, title: "Next")])
    }

    @Test func writtenBranchesReadBackTheSame() throws {
        var engine = try GraphEngine(state: .newMap(title: "Plan"))
        let rootID = try #require(engine.state.map.rootNodeID)
        let titles = ["- dash", "1. number", "# hash", "> quote", "\\slash", "[ ] box", "plain", "two\nlines"]
        var ids: [NodeID] = []
        for title in titles {
            let id = NodeID()
            _ = try engine.execute(AddNodeCommand(nodeID: id, .child(of: ids.last ?? rootID), title: title, note: title == "plain" ? "Note line\n> quoted" : nil))
            ids.append(id)
        }

        let text = BranchText.markdown(for: [rootID], in: engine.state)
        let items = BranchText.outline(from: text)

        #expect(items.map(\.title) == ["Plan"] + titles.dropLast() + ["two lines"])
        #expect(items.map(\.depth) == Array(0...titles.count))
        #expect(items.first { $0.title == "plain" }?.note == "Note line\n> quoted")
    }

    @Test func collapsedBranchesAreCopiedWhole() throws {
        var engine = try GraphEngine(state: .newMap(title: "Plan"))
        let rootID = try #require(engine.state.map.rootNodeID)
        let parent = NodeID()
        _ = try engine.execute(AddNodeCommand(nodeID: parent, .child(of: rootID), title: "Closed"))
        _ = try engine.execute(AddNodeCommand(.child(of: parent), title: "Hidden"))
        _ = try engine.execute(UpdateNodeCommand(nodeID: parent, .isCollapsed(true)))

        #expect(BranchText.markdown(for: [parent], in: engine.state) == "- Closed\n  - Hidden\n")
    }
}

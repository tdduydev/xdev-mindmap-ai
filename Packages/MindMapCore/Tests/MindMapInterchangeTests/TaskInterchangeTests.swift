import Foundation
import MindMapDomain
import MindMapGraph
@testable import MindMapInterchange
import Testing

@Suite("Task boxes in Markdown")
struct TaskInterchangeTests {
    static func taskMap() throws -> GraphState {
        try GraphState.imported(from: OutlineDraft(items: [
            .init(depth: 0, title: "Plan"),
            .init(depth: 1, title: "Launch", taskState: .open),
            .init(depth: 2, title: "Ship", taskState: .done),
            .init(depth: 2, title: "[ ] looks boxed", taskState: .open),
            .init(depth: 2, title: "Docs", link: TopicLink(string: "https://example.com"), taskState: .open),
            .init(depth: 2, title: "Plain"),
        ]), title: "Plan")
    }

    @Test func markdownWritesTaskBoxes() throws {
        let text = try MarkdownOutline.export(Self.taskMap(), options: .init(headingLevels: 2))
        #expect(text == """
        # Plan

        ## [ ] Launch

        - [x] Ship
        - [ ] \\[ ] looks boxed
        - [ ] [Docs](https://example.com)
        - Plain

        """)
    }

    @Test(arguments: [0, 1, 2, 3])
    func markdownReadsTaskBoxesBack(headingLevels: Int) throws {
        let text = try MarkdownOutline.export(Self.taskMap(), options: .init(headingLevels: headingLevels))
        let draft = MarkdownOutline.parse(text)

        #expect(draft.items.map(\.title) == ["Plan", "Launch", "Ship", "[ ] looks boxed", "Docs", "Plain"])
        #expect(draft.items.map(\.taskState) == [nil, .open, .done, .open, .open, nil])
        #expect(draft.items[4].link?.string == "https://example.com")
    }

    @Test func importReadsGitHubTaskLists() throws {
        let draft = MarkdownOutline.parse("# Plan\n- [ ] Open\n- [X] Done\n- [x]\n- \\[ ] text\n")
        let state = try GraphState.imported(from: draft, title: "")

        #expect(state.firstNode(titled: "Open")?.taskState == .open)
        #expect(state.firstNode(titled: "Done")?.taskState == .done)
        #expect(state.firstNode(titled: "")?.taskState == .done)
        #expect(state.firstNode(titled: "[ ] text")?.taskState == nil)
    }

    @Test func aSingleTaskHeadingBecomesATaskCentralTopic() throws {
        let state = try GraphState.imported(from: MarkdownOutline.parse("# [x] Plan\n- A\n"), title: "")
        #expect(state.root?.title == "Plan")
        #expect(state.root?.taskState == .done)
    }

    @Test func pastingTasksIntoAMapIsOneUndoStep() throws {
        var engine = try GraphEngine(state: GraphState.imported(from: OutlineDraft(items: [.init(depth: 0, title: "Root")]), title: ""))
        let rootID = try #require(engine.state.map.rootNodeID)
        let before = engine.state

        try engine.execute(InsertOutlineCommand(MarkdownOutline.parse("- [ ] A\n- [x] B\n"), under: rootID))
        let after = engine.state
        #expect(after.firstNode(titled: "B")?.taskState == .done)

        _ = engine.undo()
        #expect(sameContent(engine.state, before))
        _ = engine.redo()
        #expect(sameContent(engine.state, after))
    }
}

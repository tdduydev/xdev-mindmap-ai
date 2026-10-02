import Foundation
import MindMapDomain
import MindMapGraph
@testable import MindMapInterchange
import Testing

@Suite("Markdown outlines")
struct MarkdownOutlineTests {
    // MARK: Reading

    @Test func headingsNestByLevel() {
        let draft = MarkdownOutline.parse("""
        # Plan
        ## Goals
        ### Ship
        ## Risks
        """)

        #expect(draft.outline == """
        Plan
          Goals
            Ship
          Risks
        """)
    }

    @Test func aSkippedHeadingLevelNestsOneDeep() {
        let draft = MarkdownOutline.parse("# Plan\n### Detail\n## Goals\n")

        #expect(draft.outline == "Plan\n  Detail\n  Goals")
    }

    @Test func listsNestUnderTheirHeadingAndEachOther() {
        let draft = MarkdownOutline.parse("""
        # Plan
        - Goals
          - Ship
            1. Beta
            2) Release
        - Risks
        ## Budget
        * Costs
        """)

        #expect(draft.outline == """
        Plan
          Goals
            Ship
              Beta
              Release
          Risks
          Budget
            Costs
        """)
    }

    @Test func paragraphsBecomeNotesOfTheNearestTopic() {
        let draft = MarkdownOutline.parse("""
        # Plan

        Why we plan.

        Second paragraph.

        - Goals
          Indented under goals.
        - Risks

        Back in the Plan section.
        """)

        #expect(draft.outline == """
        Plan [Why we plan.

        Second paragraph.

        Back in the Plan section.]
          Goals [Indented under goals.]
          Risks
        """)
    }

    @Test func textBeforeTheFirstTopicGoesToItsNote() {
        let draft = MarkdownOutline.parse("Intro line.\n\n# Plan\n\nBody.\n")

        #expect(draft.items.count == 1)
        #expect(draft.items[0].note == "Intro line.\n\nBody.")
    }

    @Test func codeFencesStayInTheNoteAsWritten() {
        let draft = MarkdownOutline.parse("""
        # Plan

        ```swift
        # not a heading
        - not a list

        let x = 1
        ```
        ## Next
        """)

        #expect(draft.items.map(\.title) == ["Plan", "Next"])
        #expect(draft.items[0].note == "```swift\n# not a heading\n- not a list\n\nlet x = 1\n```")
    }

    @Test func frontMatterAndThematicBreaksAreSkipped() {
        let draft = MarkdownOutline.parse("---\ntitle: x\n---\n# Plan\n\n***\n\n## Goals\n")

        #expect(draft.outline == "Plan\n  Goals")
    }

    @Test func taskBoxesAndClosingHashesAreDropped() {
        let draft = MarkdownOutline.parse("# Plan ##\n- [ ] Open\n- [x] Done\n")

        #expect(draft.items.map(\.title) == ["Plan", "Open", "Done"])
    }

    @Test func inlineMarkupIsKeptAsWritten() {
        let draft = MarkdownOutline.parse("# **Bold** plan\n- see [docs](https://example.com)\n")

        #expect(draft.items.map(\.title) == ["**Bold** plan", "see [docs](https://example.com)"])
    }

    @Test func hashWithoutASpaceIsNotAHeading() {
        let draft = MarkdownOutline.parse("# Plan\n#hashtag\n")

        #expect(draft.items.count == 1)
        #expect(draft.items[0].note == "#hashtag")
    }

    @Test func textWithoutHeadingsOrListsReadsAsPlainText() {
        let draft = MarkdownOutline.parse("Plan\n\tGoals\n\tRisks\n")

        #expect(draft.outline == "Plan\n  Goals\n  Risks")
    }

    // MARK: Writing

    @Test func exportUsesHeadingsForTwoLevelsThenLists() throws {
        let state = try GraphState.imported(from: PlainTextOutline.parse("""
        Plan
        \tGoals
        \t\tShip
        \t\t\tBeta
        \tRisks
        """), title: "")

        #expect(try MarkdownOutline.export(state) == """
        # Plan

        ## Goals

        - Ship
          - Beta

        ## Risks

        """)
    }

    @Test func exportCanUseListsOnly() throws {
        let state = try GraphState.imported(from: PlainTextOutline.parse("Plan\n\tGoals\n\t\tShip\n"), title: "")

        let text = try MarkdownOutline.export(state, options: .init(headingLevels: 0))

        #expect(text == "- Plan\n  - Goals\n    - Ship\n")
    }

    @Test func notesAreOptional() throws {
        let draft = OutlineDraft(items: [
            .init(depth: 0, title: "Plan", note: "Why"),
            .init(depth: 1, title: "Goals"),
            .init(depth: 2, title: "Ship", note: "Soon"),
        ])
        let state = try GraphState.imported(from: draft, title: "")

        #expect(try MarkdownOutline.export(state) == "# Plan\n\nWhy\n\n## Goals\n\n- Ship\n\n  Soon\n")
        #expect(try MarkdownOutline.export(state, options: .init(includeNotes: false)) == "# Plan\n\n## Goals\n\n- Ship\n")
    }

    @Test func exportOfABranch() throws {
        let state = try GraphState.imported(from: MarkdownOutline.parse("# Plan\n## Goals\n- Ship\n## Risks\n"), title: "")
        let goals = try #require(state.firstNode(titled: "Goals"))

        #expect(try MarkdownOutline.export(state, branch: goals.id) == "# Goals\n\n## Ship\n")
    }

    @Test func exportOfAMissingBranchThrows() throws {
        let state = try GraphState.imported(from: MarkdownOutline.parse("# Plan\n"), title: "")

        #expect(throws: InterchangeError.topicNotFound) {
            try MarkdownOutline.export(state, branch: NodeID())
        }
    }

    @Test func exportIncludesCollapsedBranches() throws {
        var engine = try GraphEngine(state: GraphState.imported(from: MarkdownOutline.parse("# Plan\n## Goals\n- Ship\n"), title: ""))
        let goals = try #require(engine.state.firstNode(titled: "Goals"))
        try engine.execute(UpdateNodeCommand(nodeID: goals.id, .isCollapsed(true)))

        #expect(try MarkdownOutline.export(engine.state).contains("- Ship"))
    }

    // MARK: Round trips

    @Test func markdownToMapToMarkdownKeepsTheText() throws {
        let markdown = """
        # Kế hoạch

        Ghi chú của sơ đồ.

        ## Mục tiêu

        - Ship
          - Beta

            Two lines
            of note.
          - Release
        - Marketing

        ## Rủi ro

        """
        let state = try GraphState.imported(from: MarkdownOutline.parse(markdown), title: "")

        #expect(try MarkdownOutline.export(state) == markdown)
    }

    @Test(arguments: [
        "# looks like a heading",
        "- looks like a bullet",
        "1. looks numbered",
        "12) also numbered",
        "> a quote",
        "---",
        "```",
        "[ ] a task box",
        "\\ backslash first",
        "ends with #",
        "ends with \\#",
        "#",
        "",
        "  leading spaces",
    ])
    func titlesThatLookLikeMarkdownSurvive(title: String) throws {
        // The title appears at each level that is written differently: heading and list item.
        let draft = OutlineDraft(items: [
            .init(depth: 0, title: title),
            .init(depth: 1, title: "Section"),
            .init(depth: 2, title: title),
        ])
        let state = try GraphState.imported(from: draft, title: "")

        let reread = MarkdownOutline.parse(try MarkdownOutline.export(state))

        #expect(reread.items.map(\.title) == draft.items.map(\.title).map { $0.trimmingCharacters(in: .whitespaces) })
        #expect(reread.items.map(\.depth) == [0, 1, 2])
    }

    @Test func notesThatLookLikeMarkdownSurvive() throws {
        let note = "# not a heading\n- not a list\n> not a quote\n\n```\n# inside code\n```\n```unclosed"
        let draft = OutlineDraft(items: [
            .init(depth: 0, title: "Plan", note: note),
            .init(depth: 1, title: "Goals"),
            .init(depth: 2, title: "Ship", note: note),
            .init(depth: 2, title: "After"),
        ])
        let state = try GraphState.imported(from: draft, title: "")

        let reread = MarkdownOutline.parse(try MarkdownOutline.export(state))

        #expect(reread == draft)
    }

    @Test func multiLineTitlesBecomeOneLine() throws {
        let draft = OutlineDraft(items: [.init(depth: 0, title: "Plan"), .init(depth: 1, title: "Two\nlines")])
        let state = try GraphState.imported(from: draft, title: "")

        #expect(try MarkdownOutline.export(state) == "# Plan\n\n## Two lines\n")
    }
}

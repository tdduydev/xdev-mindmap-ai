import Foundation
import MindMapDomain
import MindMapGraph
@testable import MindMapInterchange
import Testing

@Suite("Plain text outlines")
struct PlainTextOutlineTests {
    @Test func tabsNestTopics() {
        let draft = PlainTextOutline.parse("Plan\n\tGoals\n\t\tShip\n\tRisks\n")

        #expect(draft.outline == """
        Plan
          Goals
            Ship
          Risks
        """)
    }

    @Test func anyNumberOfSpacesPerLevelNests() {
        let draft = PlainTextOutline.parse("""
        Plan
           Goals
              Ship
           Risks
        """)

        #expect(draft.outline == """
        Plan
          Goals
            Ship
          Risks
        """)
    }

    @Test func tabsAndSpacesMixByColumn() {
        // A tab reaches column 4, the same as four spaces.
        let draft = PlainTextOutline.parse("Plan\n\tGoals\n    Risks\n\t  Detail\n")

        #expect(draft.outline == """
        Plan
          Goals
          Risks
            Detail
        """)
    }

    @Test func outdentingGoesUpToTheTopicItPasses() {
        // "C" is indented less than "B" but more than "A": it goes up past "B"
        // and becomes A's child, next to B.
        let draft = PlainTextOutline.parse("""
        A
              B
          C
        D
        """)

        #expect(draft.outline == """
        A
          B
          C
        D
        """)
    }

    @Test func bulletsAndBlankLinesAreDropped() {
        let draft = PlainTextOutline.parse("- Plan\n\n  * Goals\n  + Risks\n  • Costs\n")

        #expect(draft.outline == """
        Plan
          Goals
          Risks
          Costs
        """)
    }

    @Test func quoteLinesAreNotesOfTheTopicBefore() {
        let draft = PlainTextOutline.parse("Plan\n\t> First line\n\t>\n\t> Second\nNext\n")

        #expect(draft.items[0].note == "First line\n\nSecond")
        #expect(draft.items[1].note == nil)
    }

    @Test func windowsAndOldMacLineEndingsSplitTheSame() {
        let draft = PlainTextOutline.parse("Plan\r\n\tGoals\r\tRisks")

        #expect(draft.outline == "Plan\n  Goals\n  Risks")
    }

    @Test func vietnameseTitlesAreKept() {
        let draft = PlainTextOutline.parse("Kế hoạch\n\tMục tiêu quý 4\n")

        #expect(draft.items.map(\.title) == ["Kế hoạch", "Mục tiêu quý 4"])
    }

    @Test func emptyTextIsAnEmptyDraft() {
        #expect(PlainTextOutline.parse("").isEmpty)
        #expect(PlainTextOutline.parse("\n  \n\t\n").isEmpty)
    }

    @Test func exportUsesOneTabPerLevelAndQuotesNotes() throws {
        let state = try GraphState.imported(
            from: OutlineDraft(items: [
                .init(depth: 0, title: "Plan"),
                .init(depth: 1, title: "Goals", note: "Why\n\nHow"),
                .init(depth: 2, title: "Ship"),
            ]),
            title: "Untitled"
        )

        #expect(try PlainTextOutline.export(state) == "Plan\n\tGoals\n\t\t> Why\n\t\t>\n\t\t> How\n\t\tShip\n")
        #expect(try PlainTextOutline.export(state, includeNotes: false) == "Plan\n\tGoals\n\t\tShip\n")
    }

    @Test func exportOfABranchStartsAtTopLevel() throws {
        let state = try GraphState.imported(from: PlainTextOutline.parse("Plan\n\tGoals\n\t\tShip\n\tRisks\n"), title: "")
        let goals = try #require(state.firstNode(titled: "Goals"))

        #expect(try PlainTextOutline.export(state, branch: goals.id) == "Goals\n\tShip\n")
    }

    @Test func titlesThatLookLikeSyntaxSurviveARoundTrip() throws {
        let titles = ["> not a note", "- not a bullet", "\\backslash", "-", "• dot", "plain"]
        let draft = OutlineDraft(items: [.init(depth: 0, title: "Root")] + titles.map { .init(depth: 1, title: $0) })
        let state = try GraphState.imported(from: draft, title: "")

        let reread = PlainTextOutline.parse(try PlainTextOutline.export(state))

        #expect(reread == draft)
    }

    @Test func roundTripKeepsStructureAndNotes() throws {
        let text = "Plan\n\t> Kept\n\tGoals\n\t\tShip\n\t\t\t> Line one\n\t\t\t>\n\t\t\t> Line two\n\tRisks\n"
        let state = try GraphState.imported(from: PlainTextOutline.parse(text), title: "")

        #expect(try PlainTextOutline.export(state) == text)
    }
}

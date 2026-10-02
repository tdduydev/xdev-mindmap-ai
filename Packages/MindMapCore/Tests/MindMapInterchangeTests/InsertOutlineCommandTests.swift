import Foundation
import MindMapDomain
import MindMapGraph
@testable import MindMapInterchange
import Testing

@Suite("Inserting an outline")
struct InsertOutlineCommandTests {
    private func engine(_ text: String) throws -> GraphEngine {
        try GraphEngine(state: GraphState.imported(from: PlainTextOutline.parse(text), title: "", now: fixedDate))
    }

    @Test func insertsUnderTheParentInOrder() throws {
        var engine = try engine("Plan\n\tGoals\n")
        let plan = try #require(engine.state.map.rootNodeID)
        let draft = PlainTextOutline.parse("Risks\n\tCost\nTeam\n")

        let command = InsertOutlineCommand(draft, under: plan)
        try engine.execute(command)

        #expect(engine.state.outline == """
        Plan
          Goals
          Risks
            Cost
          Team
        """)
        #expect(command.topNodeIDs.compactMap { engine.state.node($0)?.title } == ["Risks", "Team"])
        #expect(command.entries.allSatisfy { engine.state.node($0.id)?.metadata.origin == .imported })
    }

    @Test func placementPutsTheFirstTopicAndTheRestFollow() throws {
        var engine = try engine("Plan\n\tA\n\tB\n")
        let plan = try #require(engine.state.map.rootNodeID)
        let a = try #require(engine.state.firstNode(titled: "A"))

        try engine.execute(InsertOutlineCommand(PlainTextOutline.parse("X\nY\n"), under: plan, at: .after(a.id)))

        #expect(engine.state.children(of: plan).map(\.title) == ["A", "X", "Y", "B"])
    }

    @Test func insertIsOneUndoStepAndRedoRestoresTheSameTopics() throws {
        var engine = try engine("Plan\n")
        let plan = try #require(engine.state.map.rootNodeID)
        let before = engine.state
        let command = InsertOutlineCommand(PlainTextOutline.parse("A\n\tA1\nB\n"), under: plan, origin: .ai)

        try engine.execute(command)
        let after = engine.state

        #expect(engine.undo() != nil)
        #expect(sameContent(engine.state, before))
        #expect(!engine.canUndo)

        #expect(engine.redo() != nil)
        #expect(sameContent(engine.state, after))
        #expect(command.entries.allSatisfy { engine.state.node($0.id)?.metadata.origin == .ai })
    }

    @Test func insertOpensACollapsedParent() throws {
        var engine = try engine("Plan\n\tGoals\n\t\tShip\n")
        let goals = try #require(engine.state.firstNode(titled: "Goals"))
        try engine.execute(UpdateNodeCommand(nodeID: goals.id, .isCollapsed(true)))

        try engine.execute(InsertOutlineCommand(PlainTextOutline.parse("New\n"), under: goals.id))

        #expect(engine.state.node(goals.id)?.isCollapsed == false)
    }

    @Test func unknownParentChangesNothing() throws {
        var engine = try engine("Plan\n")
        let before = engine.state

        #expect(throws: GraphError.self) {
            try engine.execute(InsertOutlineCommand(PlainTextOutline.parse("A\n"), under: NodeID()))
        }
        #expect(sameContent(engine.state, before))
        #expect(!engine.canUndo)
    }

    @Test func emptyDraftAddsNothingToHistory() throws {
        var engine = try engine("Plan\n")
        let plan = try #require(engine.state.map.rootNodeID)

        let changes = try engine.execute(InsertOutlineCommand(OutlineDraft(), under: plan))

        #expect(changes.isEmpty)
        #expect(!engine.canUndo)
    }

    @Test func draftDepthsAreClampedToAValidTree() {
        let draft = OutlineDraft(items: [
            .init(depth: 2, title: "A"),
            .init(depth: 5, title: "B"),
            .init(depth: -1, title: "C"),
        ])

        #expect(draft.items.map(\.depth) == [0, 1, 0])
    }

    // MARK: New maps

    @Test func oneTopLevelTopicBecomesTheCentralTopic() throws {
        let state = try GraphState.imported(from: MarkdownOutline.parse("# Plan\n\nWhy.\n\n## Goals\n"), title: "plan.md")

        #expect(state.map.title == "Plan")
        #expect(state.root?.title == "Plan")
        #expect(state.root?.note == "Why.")
        #expect(state.outline == "Plan [Why.]\n  Goals")
        #expect(GraphValidator.validate(state).isEmpty)
    }

    @Test func severalTopLevelTopicsGoUnderACentralTopicNamedForTheFile() throws {
        let state = try GraphState.imported(from: PlainTextOutline.parse("A\nB\n\tB1\n"), title: "Notes")

        #expect(state.map.title == "Notes")
        #expect(state.outline == "Notes\n  A\n  B\n    B1")
        #expect(state.nodes.values.allSatisfy { $0.metadata.origin == .imported })
    }

    @Test func emptyDocumentIsRefused() {
        #expect(throws: InterchangeError.emptyDocument) {
            try GraphState.imported(from: OutlineDraft(), title: "Empty")
        }
    }

    @Test func veryDeepOutlinesDoNotOverflowTheStack() throws {
        // The text itself grows with the square of the depth (one tab per level
        // per line), so this stays well short of what a real file could hold.
        let depth = 3_000
        let text = (0..<depth).map { String(repeating: "\t", count: $0) + "T\($0)" }.joined(separator: "\n")

        let state = try GraphState.imported(from: PlainTextOutline.parse(text), title: "")
        let exported = try MarkdownOutline.export(state, options: .init(headingLevels: 0))

        #expect(state.nodes.count == depth)
        #expect(MarkdownOutline.parse(exported).items.count == depth)
    }
}

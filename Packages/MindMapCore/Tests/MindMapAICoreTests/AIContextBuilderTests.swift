import Foundation
import MindMapAICore
import MindMapDomain
import MindMapGraph
import MindMapTestSupport
import Testing

struct AIContextBuilderTests {
    private let outline = """
    Launch
      Marketing
        Social
          Posts
            Drafts
              Old
        Press
      Product
        Beta
      Sales
    """

    private func context(
        _ fixture: OutlineFixture,
        focus: String,
        limits: AIContextLimits = AIContextLimits()
    ) throws -> AIContext {
        try AIContextBuilder(limits: limits).context(
            for: fixture[focus],
            in: fixture.state,
            language: .english,
            userLocaleIdentifier: "en_US"
        )
    }

    @Test func includesFocusPathChildrenAndSiblings() throws {
        let fixture = try OutlineFixture(outline, mapTitle: "Launch plan")
        let context = try context(fixture, focus: "Marketing")

        #expect(context.mapTitle == "Launch plan")
        #expect(context.focus.title == "Marketing")
        #expect(context.ancestors.map(\.title) == ["Launch"])
        #expect(context.siblings.map(\.title) == ["Product", "Sales"])
        #expect(context.descendants.map(\.title) == ["Social", "Posts", "Drafts", "Press"])
        #expect(context.descendants.map(\.depth) == [1, 2, 3, 1])
        #expect(context.language == .english)
        #expect(context.userLocaleIdentifier == "en_US")
        #expect(context.estimatedTokens > 0)
    }

    @Test func stopsAtTheDepthLimitAndCountsWhatItLeftOut() throws {
        let fixture = try OutlineFixture(outline)
        let context = try context(fixture, focus: "Marketing")

        // Default depth is 3: Old is the fourth level under Marketing.
        #expect(!context.descendants.map(\.title).contains("Old"))
        #expect(context.omittedDescendantCount == 1)
        #expect(context.isTruncated)
    }

    @Test func capsTheNumberOfDescendants() throws {
        let fixture = try OutlineFixture(outline)
        let context = try context(fixture, focus: "Launch", limits: AIContextLimits(maximumDescendants: 3))

        // Breadth first: the three children of the root, nothing deeper.
        #expect(context.descendants.map(\.title) == ["Marketing", "Product", "Sales"])
        #expect(context.omittedDescendantCount == 6)
    }

    @Test func aTightBudgetKeepsTheNearestTopics() throws {
        let fixture = try OutlineFixture(outline)
        var limits = AIContextLimits()
        limits.tokenBudget = 30
        let context = try context(fixture, focus: "Marketing", limits: limits)

        #expect(context.focus.title == "Marketing")
        #expect(context.estimatedTokens <= 30)
        // Whatever made it in is a prefix by level: no grandchild without every child.
        if context.descendants.contains(where: { $0.depth == 2 }) {
            #expect(context.descendants.filter { $0.depth == 1 }.count == 2)
        }
        #expect(context.omittedDescendantCount > 0)
    }

    @Test func aLongPathKeepsTheRootAndTheNearestAncestors() throws {
        let fixture = try OutlineFixture("""
        L0
          L1
            L2
              L3
                L4
                  L5
        """)
        let context = try context(fixture, focus: "L5", limits: AIContextLimits(maximumAncestors: 3))

        #expect(context.ancestors.map(\.title) == ["L0", "L3", "L4"])
        #expect(context.ancestors.map(\.depth) == [-5, -2, -1])
    }

    @Test func includesTopicsJoinedByACrossLink() throws {
        let fixture = try OutlineFixture(outline)
        let state = fixture.state
        let edge = MindEdge(mapID: state.map.id, sourceNodeID: fixture["Beta"], targetNodeID: fixture["Press"])
        let linked = GraphState(map: state.map, nodes: Array(state.nodes.values), edges: [edge])

        let context = try AIContextBuilder().context(
            for: fixture["Press"],
            in: linked,
            language: .english,
            userLocaleIdentifier: "en_US"
        )

        #expect(context.linkedTopics.map(\.title) == ["Beta"])
    }

    @Test func sendsTheNoteOfTheFocusOnly() throws {
        var fixture = try OutlineFixture(outline)
        try fixture.engine.execute(UpdateNodeCommand(nodeID: fixture["Marketing"], .note("Budget is small")))
        try fixture.engine.execute(UpdateNodeCommand(nodeID: fixture["Social"], .note("Not for the model")))

        let context = try context(fixture, focus: "Marketing")

        #expect(context.focus.note == "Budget is small")
        #expect(context.descendants.allSatisfy { $0.note == nil })
    }

    @Test func shortensLongTitlesToOneLine() throws {
        var fixture = try OutlineFixture("Root")
        try fixture.engine.execute(UpdateNodeCommand(
            nodeID: fixture["Root"],
            .title("First line\n  second line " + String(repeating: "x", count: 200))
        ))

        let context = try context(fixture, focus: "Root", limits: AIContextLimits(maximumTitleLength: 20))

        #expect(context.focus.title.count == 20)
        #expect(context.focus.title.hasPrefix("First line second"))
        #expect(context.focus.title.hasSuffix("…"))
    }

    @Test func refusesATopicThatIsNotInTheMap() throws {
        let fixture = try OutlineFixture(outline)
        #expect(throws: GraphError.nodeNotFound(fixture["Sales"])) {
            let other = try OutlineFixture("Other")
            _ = try AIContextBuilder().context(
                for: fixture["Sales"],
                in: other.state,
                language: .english,
                userLocaleIdentifier: "en_US"
            )
        }
    }

    @Test func chunksCoverTheWholeBranchOnceAndInOrder() throws {
        var lines = ["Root"]
        for index in 1...40 {
            lines.append("  Topic number \(index)")
            lines.append("    Detail number \(index)")
        }
        let fixture = try OutlineFixture(lines.joined(separator: "\n"))
        var limits = AIContextLimits()
        limits.tokenBudget = 120

        let chunks = try AIContextBuilder(limits: limits).chunkContexts(
            for: fixture["Root"],
            in: fixture.state,
            language: .english,
            userLocaleIdentifier: "en_US"
        )

        #expect(chunks.count > 1)
        let covered = chunks.flatMap(\.descendants).map(\.nodeID)
        #expect(covered == fixture.state.descendants(of: fixture["Root"]))
        #expect(chunks.allSatisfy { $0.estimatedTokens <= 120 })
        #expect(chunks.allSatisfy { $0.focus.nodeID == fixture["Root"] && $0.omittedDescendantCount == 0 })
    }

    @Test func onlyASummaryOfATruncatedContextIsPartial() throws {
        let fixture = try OutlineFixture(outline)
        let truncated = try context(fixture, focus: "Marketing")
        let whole = try context(fixture, focus: "Product")

        #expect(SummarizeRequest(context: truncated).isPartial)
        #expect(!SummarizeRequest(context: whole).isPartial)
        // The partial summaries of every chunk cover what the context left out.
        #expect(!SummarizeRequest(context: truncated, partialSummaries: ["Part one.", "Part two."]).isPartial)
    }

    @Test func aSmallBranchIsOneChunk() throws {
        let fixture = try OutlineFixture(outline)
        let chunks = try AIContextBuilder().chunkContexts(
            for: fixture["Product"],
            in: fixture.state,
            language: .vietnamese,
            userLocaleIdentifier: "vi_VN"
        )
        #expect(chunks.count == 1)
        #expect(chunks.first?.descendants.map(\.title) == ["Beta"])
        #expect(chunks.first?.language == .vietnamese)
    }
}

struct TokenEstimatorTests {
    @Test func countsVietnameseAboutOneTokenPerCharacter() {
        #expect(TokenEstimator.estimate("Kế hoạch") == "Kế hoạch".count)
    }

    @Test func countsEnglishAtAboutThreeCharactersPerToken() {
        #expect(TokenEstimator.estimate("Marketing plan") == 5)
        #expect(TokenEstimator.estimate("") == 0)
    }

    @Test func budgetFollowsTheContextSize() {
        #expect(AIContextLimits(contextSize: 4_096).tokenBudget == 1_638)
        #expect(AIContextLimits(contextSize: 8_192).tokenBudget == 3_276)
        #expect(AIContextLimits(contextSize: nil).tokenBudget == AIContextLimits(contextSize: 4_096).tokenBudget)
        #expect(AIContextLimits(contextSize: 100).tokenBudget == 256)
    }
}

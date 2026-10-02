import Foundation
import MindMapAICore
import MindMapDomain
import MindMapGraph
import MindMapTestSupport
import Testing

struct MockAIProviderTests {
    private func expandRequest(_ fixture: OutlineFixture, focus: String, language: AILanguage = .english) throws -> ExpandTopicRequest {
        let context = try AIContextBuilder().context(
            for: fixture[focus],
            in: fixture.state,
            language: language,
            userLocaleIdentifier: language.locale.identifier
        )
        return ExpandTopicRequest(context: context)
    }

    /// The whole path a suggestion takes: context, provider, translator, engine.
    @Test func aSuggestionFlowsFromContextToOneUndoStep() async throws {
        var fixture = try OutlineFixture("""
        Wedding
          Venue
          Guests
        """)
        let provider = MockAIProvider()
        provider.enqueue(.proposal(.suggestions(["Music", "Photos"], under: fixture["Wedding"])), for: .expandTopic)

        let request = try expandRequest(fixture, focus: "Wedding")
        let proposal = try await provider.expandTopic(request)
        let accepted = try ProposalTranslator.accept(proposal, in: fixture.engine)
        try fixture.engine.execute(accepted.command)

        #expect(fixture.childTitles(of: "Wedding") == ["Venue", "Guests", "Music", "Photos"])
        #expect(provider.requests == [.expandTopic(request)])
        #expect(request.context.descendants.map(\.title) == ["Venue", "Guests"])

        fixture.engine.undo()
        #expect(fixture.childTitles(of: "Wedding") == ["Venue", "Guests"])
        fixture.engine.redo()
        #expect(fixture.childTitles(of: "Wedding") == ["Venue", "Guests", "Music", "Photos"])
    }

    @Test func anInvalidAnswerIsDroppedAndTheMapIsUntouched() async throws {
        let fixture = try OutlineFixture("Root")
        let provider = MockAIProvider()
        let broken = AIProposal(feature: .expandTopic, anchor: .node(fixture["Root"]), topics: [
            ProposedTopic(temporaryID: "t1", title: "A"),
            ProposedTopic(temporaryID: "t1", title: "B"),
        ])
        provider.enqueue(.proposal(broken), for: .expandTopic)

        let request = try expandRequest(fixture, focus: "Root")
        let proposal = try await provider.expandTopic(request)

        #expect(throws: ProposalError.duplicateTemporaryID("t1")) {
            try ProposalTranslator.accept(proposal, in: fixture.engine)
        }
    }

    @Test func refusesWhenTheModelIsNotReady() async throws {
        let fixture = try OutlineFixture("Root")
        let provider = MockAIProvider(capabilities: AICapabilities(model: .appleIntelligenceOff))
        provider.enqueue(.proposal(.suggestions(["A"], under: fixture["Root"])), for: .expandTopic)
        let request = try expandRequest(fixture, focus: "Root")

        await #expect(throws: AIError.unavailable(.appleIntelligenceOff)) {
            try await provider.expandTopic(request)
        }
    }

    @Test func refusesALanguageTheModelDoesNotSupport() async throws {
        let fixture = try OutlineFixture("Gốc")
        let provider = MockAIProvider(
            capabilities: AICapabilities(model: .ready, supportedLanguages: [.english], contextSize: 4_096)
        )

        let request = try expandRequest(fixture, focus: "Gốc", language: .vietnamese)

        await #expect(throws: AIError.unavailable(.languageUnsupported)) {
            try await provider.expandTopic(request)
        }
    }

    @Test func passesScriptedErrorsThroughAndFailsWhenTheScriptRunsOut() async throws {
        let fixture = try OutlineFixture("Root")
        let provider = MockAIProvider()
        provider.enqueue(.failure(.guardrailViolation), for: .brainstorm)
        let context = try AIContextBuilder().context(
            for: fixture["Root"],
            in: fixture.state,
            language: .english,
            userLocaleIdentifier: "en_US"
        )

        await #expect(throws: AIError.guardrailViolation) {
            try await provider.brainstorm(BrainstormRequest(context: context, question: "What could go wrong?"))
        }
        await #expect(throws: AIError.generationFailed) {
            try await provider.brainstorm(BrainstormRequest(context: context))
        }
    }

    @Test func answersRewritesAndSummaries() async throws {
        let fixture = try OutlineFixture("Root")
        let provider = MockAIProvider()
        let context = try AIContextBuilder().context(
            for: fixture["Root"],
            in: fixture.state,
            language: .english,
            userLocaleIdentifier: "en_US"
        )
        let rewrite = AIRewrite(nodeID: fixture["Root"], originalTitle: "Root", suggestions: ["Origin"])
        let summary = AISummary(nodeID: fixture["Root"], text: "A single topic.")
        provider.enqueue(.rewrite(rewrite), for: .rewrite)
        provider.enqueue(.summary(summary), for: .summarize)

        #expect(try await provider.rewrite(RewriteRequest(context: context, style: .shorter)) == rewrite)
        #expect(try await provider.summarize(SummarizeRequest(context: context)) == summary)
    }

    @Test func capabilitiesCanChangeBetweenRequests() async {
        let provider = MockAIProvider(capabilities: AICapabilities(model: .modelDownloading))
        #expect(await provider.capabilities().model == .modelDownloading)

        provider.setCapabilities(.readyForTesting)
        #expect(await provider.capabilities().availability(for: .summarize, in: .vietnamese) == .ready)
    }
}

import Foundation
import FoundationModels
@testable import MindMapAIApple
import MindMapAICore
import MindMapGraph
import MindMapTestSupport
import Testing

struct AppleCapabilityProbeTests {
    @Test func mapsEveryFrameworkStateToOneOfOurs() {
        #expect(AppleCapabilityProbe.status(of: .available) == .ready)
        #expect(AppleCapabilityProbe.status(of: .unavailable(.deviceNotEligible)) == .deviceNotEligible)
        #expect(AppleCapabilityProbe.status(of: .unavailable(.appleIntelligenceNotEnabled)) == .appleIntelligenceOff)
        #expect(AppleCapabilityProbe.status(of: .unavailable(.modelNotReady)) == .modelDownloading)
    }

    @Test func reportsWhatTheFrameworkReports() async {
        let capabilities = await AppleFoundationModelProvider().capabilities()
        #if arch(x86_64)
        // MM-21 hides AI on Intel Macs on the strength of this.
        #expect(capabilities == .notEligible)
        #else
        #expect(capabilities.model == AppleCapabilityProbe.status(of: SystemLanguageModel.default.availability))
        if capabilities.model.isReady {
            #expect((capabilities.contextSize ?? 0) > 0)
        }
        #endif
    }
}

/// What the provider does with an answer once guided generation has filled
/// the schema; no model needed.
struct GeneratedAnswerTests {
    private let provider = AppleFoundationModelProvider()

    @Test func aMalformedTreeArrivesAsInvalidResponse() throws {
        let generated = try GeneratedMindMap(GeneratedContent(json: """
        {"title": "Garden", "topics": [
          {"temporaryID": "t1", "parentTemporaryID": "", "title": "Vegetables"},
          {"temporaryID": "t2", "parentTemporaryID": "t3", "title": "Tomatoes"},
          {"temporaryID": "t3", "parentTemporaryID": "t2", "title": "Beans"}
        ]}
        """))

        #expect(throws: AIError.invalidResponse(.cycle(temporaryID: "t2"))) {
            try provider.checked(generated.proposal(), limit: 30, feature: .generateMap)
        }
    }

    @Test func aGeneratedMapKeepsNoMoreTopicsThanAskedFor() throws {
        let generated = try GeneratedMindMap(GeneratedContent(json: """
        {"title": "Garden", "topics": [
          {"temporaryID": "t1", "parentTemporaryID": "", "title": "Vegetables"},
          {"temporaryID": "t2", "parentTemporaryID": "t1", "title": "Tomatoes"},
          {"temporaryID": "t3", "parentTemporaryID": "", "title": "Flowers"}
        ]}
        """))

        let proposal = try provider.checked(generated.proposal(), limit: 2, feature: .generateMap)

        #expect(proposal.topics.map(\.title) == ["Vegetables", "Flowers"])
        #expect(proposal.suggestedMapTitle == "Garden")
    }
}

/// Runs the real on-device model, so only where the provider will use it. That
/// is the probe, not `SystemLanguageModel.default.isAvailable`: under Rosetta
/// the framework says the model is available while an x86_64 build never uses
/// it (MM-21). Answers vary, so these check shape, not wording.
@Suite(.enabled(if: AppleCapabilityProbe.current().model.isReady), .serialized)
struct AppleFoundationModelProviderTests {
    private let provider = AppleFoundationModelProvider()

    @Test func expandsATopicIntoAProposalTheTranslatorAccepts() async throws {
        var fixture = try OutlineFixture("""
        Trip to Da Nang
          Flights
          Hotels
        """)
        let context = try AIContextBuilder().context(
            for: fixture["Trip to Da Nang"],
            in: fixture.state,
            language: .english,
            userLocaleIdentifier: "en_US"
        )

        let proposal = try await provider.expandTopic(ExpandTopicRequest(context: context, maximumTopics: 4))

        #expect(!proposal.topics.isEmpty && proposal.topics.count <= 4)
        #expect(proposal.anchor == .node(fixture["Trip to Da Nang"]))
        let accepted = try ProposalTranslator.accept(proposal, in: fixture.engine)
        try fixture.engine.execute(accepted.command)
        #expect(fixture.childTitles(of: "Trip to Da Nang").count == 2 + proposal.topics.count)
    }

    @Test func generatesAMapInVietnamese() async throws {
        let capabilities = await provider.capabilities()
        try #require(capabilities.availability(for: .generateMap, in: .vietnamese) == .ready)

        let proposal = try await provider.generateMap(GenerateMapRequest(
            prompt: "Kế hoạch học tiếng Anh trong ba tháng",
            language: .vietnamese,
            userLocaleIdentifier: "vi_VN",
            maximumTopics: 10
        ))

        #expect(proposal.anchor == .root)
        #expect(!proposal.topics.isEmpty && proposal.topics.count <= 10)
        #expect(!(proposal.suggestedMapTitle ?? "").isEmpty)
        // The app makes a new map with the suggested title, then applies the topics under its root.
        var fixture = try OutlineFixture("New map")
        let accepted = try ProposalTranslator.accept(proposal, in: fixture.engine)
        try fixture.engine.execute(accepted.command)
        #expect(fixture.state.nodes.count == 1 + proposal.topics.count)
    }
}

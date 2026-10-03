import MindMapAICore
import MindMapTestSupport
import Testing
@testable import MindMapAILocal

@Suite struct FallbackAIProviderTests {
    static let ready = AICapabilities(model: .ready, supportedLanguages: Set(AILanguage.allCases), contextSize: 4_096)
    static let notDownloaded = AICapabilities(model: .unknown)

    @Test(arguments: [
        (AICapabilities(model: .ready, supportedLanguages: [.english]), ready, AIProviderChoice.apple),
        (AICapabilities(model: .appleIntelligenceOff), ready, .local),
        (AICapabilities.notEligible, ready, .local),
        (AICapabilities(model: .unknown), ready, .local),
        // Apple Intelligence will be ready soon and is the better model.
        (AICapabilities(model: .modelDownloading), ready, .apple),
        // Nothing downloaded: the app looks as it did before the fallback.
        (AICapabilities.notEligible, notDownloaded, .apple),
        (AICapabilities(model: .appleIntelligenceOff), AICapabilities.notEligible, .apple),
    ])
    func choice(apple: AICapabilities, local: AICapabilities, expected: AIProviderChoice) {
        #expect(AIProviderChoice.choose(apple: apple, local: local) == expected)
    }

    @Test func aLanguageAppleLacksGoesToTheLocalModel() {
        let apple = AICapabilities(model: .ready, supportedLanguages: [.english, .japanese])
        #expect(AIProviderChoice.choose(apple: apple, local: Self.ready, feature: .expandTopic, language: .vietnamese) == .local)
        #expect(AIProviderChoice.choose(apple: apple, local: Self.ready, feature: .expandTopic, language: .english) == .apple)
        #expect(AIProviderChoice.choose(apple: apple, local: Self.notDownloaded, feature: .expandTopic, language: .vietnamese) == .apple)
    }

    @Test func appleIntelligenceOffUsesTheDownloadedModel() async throws {
        let apple = MockAIProvider(capabilities: AICapabilities(model: .appleIntelligenceOff))
        let engine = ScriptedEngine(#"{"topics": [{"title": "Dark room"}]}"#)
        let provider = FallbackAIProvider(apple: apple, local: readyProvider(engine))
        #expect(await provider.capabilities().model == .ready)
        let proposal = try await provider.expandTopic(ExpandTopicRequest(context: context()))
        #expect(proposal.topics.map(\.title) == ["Dark room"])
        #expect(engine.callCount == 1)
    }

    @Test func streamingGoesThroughTheChosenProvider() async throws {
        let apple = MockAIProvider(capabilities: .notEligible)
        let engine = ScriptedEngine(#"{"topics": [{"title": "Dark room"}]}"#)
        let provider = FallbackAIProvider(apple: apple, local: readyProvider(engine))
        var last: ProposalSnapshot?
        for try await snapshot in provider.streamSuggestions(.expandTopic(ExpandTopicRequest(context: context()))) {
            last = snapshot
        }
        #expect(last?.isComplete == true)
        #expect(last?.proposal.topics.map(\.title) == ["Dark room"])
    }

    @Test func appleReadyAddsTheLocalLanguages() async {
        let apple = MockAIProvider(capabilities: AICapabilities(model: .ready, supportedLanguages: [.english], contextSize: 4_096))
        let provider = FallbackAIProvider(apple: apple, local: readyProvider(ScriptedEngine("")))
        let capabilities = await provider.capabilities()
        #expect(capabilities.supportedLanguages == Set(AILanguage.allCases))
        #expect(capabilities.contextSize == 4_096)
    }

    @Test func intelMacKeepsHidingAI() async {
        let local = LocalLLMProvider(model: .qwen3_1_7B, isDeviceEligible: false, isInstalled: { true }, engine: { ScriptedEngine("") })
        let provider = FallbackAIProvider(apple: MockAIProvider(capabilities: .notEligible), local: local)
        #expect(await provider.capabilities().showsAIEntryPoints == false)
    }
}

import Foundation
import MindMapAICore
import MindMapDomain
import Testing
@testable import MindMapAILocal

@Suite struct LocalLLMProviderTests {
    @Test func notDownloadedIsNotReady() async {
        let engine = ScriptedEngine("")
        let provider = LocalLLMProvider(model: .qwen3_1_7B, isDeviceEligible: true, physicalMemory: 8 << 30,
                                        isInstalled: { false }, engine: { engine })
        #expect(await provider.capabilities().model == .unknown)
        await #expect(throws: AIError.unavailable(.unknown)) {
            try await provider.expandTopic(ExpandTopicRequest(context: context()))
        }
        #expect(engine.callCount == 0)
    }

    @Test func ineligibleDeviceHidesAI() async {
        let provider = LocalLLMProvider(model: .qwen3_1_7B, isDeviceEligible: false, physicalMemory: 8 << 30,
                                        isInstalled: { true }, engine: { ScriptedEngine("") })
        #expect(await provider.capabilities() == .notEligible)
    }

    @Test func tooLittleMemoryForTheModelIsNotEligible() async {
        let provider = LocalLLMProvider(model: .qwen3_4B, isDeviceEligible: true, physicalMemory: 6 << 30,
                                        isInstalled: { true }, engine: { ScriptedEngine("") })
        #expect(await provider.capabilities().model == .deviceNotEligible)
    }

    @Test func readyInEveryAppLanguage() async {
        let capabilities = await readyProvider(ScriptedEngine("")).capabilities()
        for language in AILanguage.allCases {
            #expect(capabilities.availability(for: .generateMap, in: language) == .ready)
        }
    }

    @Test func expandParsesFencedJSONAndKeepsTheLimit() async throws {
        let engine = ScriptedEngine("""
        ```json
        {"topics": [{"title": "Dark room"}, {"title": "No caffeine after 2 pm"}, {"title": "Wind-down routine"}]}
        ```
        """)
        let focus = context()
        let proposal = try await readyProvider(engine).expandTopic(ExpandTopicRequest(context: focus, maximumTopics: 2))
        #expect(proposal.anchor == .node(focus.focus.nodeID))
        #expect(proposal.topics.map(\.title) == ["Dark room", "No caffeine after 2 pm"])
        #expect(engine.shapes == [.topicList])
    }

    @Test func generateMapSkipsThinkingAndBuildsTheTree() async throws {
        let engine = ScriptedEngine("""
        <think>plan {not json}</think>{"title": "Ôn thi Toán", "topics": [
          {"temporaryID": "t1", "parentTemporaryID": "", "title": "Đại số"},
          {"temporaryID": "t2", "parentTemporaryID": "t1", "title": "Hàm số"}]}
        """)
        let proposal = try await readyProvider(engine).generateMap(GenerateMapRequest(prompt: "Ôn thi", language: .vietnamese, userLocaleIdentifier: "vi_VN"))
        #expect(proposal.suggestedMapTitle == "Ôn thi Toán")
        #expect(proposal.topics.map(\.parentTemporaryID) == [nil, "t1"])
    }

    @Test func aBadAnswerIsAskedForAgain() async throws {
        let engine = ScriptedEngine("Sure! Here are some ideas: Escape room", #"{"topics": [{"title": "脱出ゲーム"}]}"#)
        let proposal = try await readyProvider(engine).brainstorm(BrainstormRequest(context: context(language: .japanese)))
        #expect(proposal.topics.map(\.title) == ["脱出ゲーム"])
        #expect(engine.callCount == 2)
        #expect(engine.prompts[1].hasSuffix(LocalLLMProvider.retryReminder(for: .topicList)))
        #expect(!engine.prompts[0].contains(LocalLLMProvider.retryReminder(for: .topicList)))
    }

    @Test func twoBadAnswersAreInvalid() async {
        let loop = #"{"title": "x", "topics": [{"temporaryID": "t1", "parentTemporaryID": "t2", "title": "A"}, {"temporaryID": "t2", "parentTemporaryID": "t1", "title": "B"}]}"#
        let engine = ScriptedEngine(loop)
        await #expect(throws: AIError.self) {
            try await readyProvider(engine).generateMap(GenerateMapRequest(prompt: "x", language: .english, userLocaleIdentifier: "en_US"))
        }
        #expect(engine.callCount == LocalLLMProvider.maximumAttempts)
    }

    @Test func anEngineFailureIsNotRetried() async {
        let engine = ScriptedEngine(failing: EngineFailure())
        await #expect(throws: AIError.generationFailed) {
            try await readyProvider(engine).summarize(SummarizeRequest(context: context()))
        }
        #expect(engine.callCount == 1)
    }

    @Test func aModelThatFailsToLoadIsAGenerationFailure() async {
        let provider = LocalLLMProvider(model: .qwen3_1_7B, isDeviceEligible: true, physicalMemory: 8 << 30,
                                        isInstalled: { true }, engine: { throw EngineFailure() })
        await #expect(throws: AIError.generationFailed) {
            try await provider.summarize(SummarizeRequest(context: context()))
        }
    }

    @Test func rewriteDropsTheOriginalAndRepeats() async throws {
        let engine = ScriptedEngine(#"{"titles": ["Sleep", "Better sleep", "better sleep", "Rest well"]}"#)
        let rewrite = try await readyProvider(engine).rewrite(RewriteRequest(context: context(), style: .clearer))
        #expect(rewrite.suggestions == ["Better sleep", "Rest well"])
    }

    @Test func summaryWithoutJSONIsInvalidAfterTheRetry() async {
        let engine = ScriptedEngine("I cannot help with that.")
        await #expect(throws: AIError.invalidResponse(.empty)) {
            try await readyProvider(engine).summarize(SummarizeRequest(context: context()))
        }
        #expect(engine.callCount == 2)
    }

    @Test func brainstormAcceptsPlainStrings() async throws {
        let engine = ScriptedEngine(#"{"topics": ["Escape room", "Cooking class"]}"#)
        let proposal = try await readyProvider(engine).brainstorm(BrainstormRequest(context: context()))
        #expect(proposal.topics.map(\.title) == ["Escape room", "Cooking class"])
    }

    @Test func groupsUseTheSameChecksAsFoundationModels() async throws {
        let children = (1...4).map { GroupSuggestionTopic(reference: "T\($0)", nodeID: NodeID(), title: "Topic \($0)") }
        let request = SuggestGroupsRequest(mapTitle: "Trip", parentID: NodeID(), parentTitle: "Plan",
                                           children: children, language: .english, userLocaleIdentifier: "en_US")
        // T9 does not exist and is dropped, as AIGroupSuggestions.checked does.
        let engine = ScriptedEngine(#"{"groups": [{"title": "Before", "references": ["T1", "T2", "T9"]}]}"#)
        let groups = try await readyProvider(engine).suggestGroups(request)
        #expect(groups.groups.map(\.nodeIDs) == [[children[0].nodeID, children[1].nodeID]])
        #expect(engine.shapes == [.groups])
    }

    @Test func boundaryTitleIsOneLine() async throws {
        let request = SummarizeBoundaryRequest(mapTitle: "Trip", groupID: GroupID(), parentTitle: "Plan", currentTitle: nil,
                                               outline: [.init(depth: 0, title: "Visa")], language: .english, userLocaleIdentifier: "en_US")
        let engine = ScriptedEngine(#"{"title": "Paperwork"}"#)
        #expect(try await readyProvider(engine).summarizeBoundary(request).title == "Paperwork")
    }

    @Test func jsonObjectIgnoresBracesInStrings() {
        #expect(LocalAnswer.jsonObject(in: #"x {"summary": "a } b"} y"#) == #"{"summary": "a } b"}"#)
    }

    @Test func everySchemaIsValidJSON() throws {
        for shape in LocalOutputShape.allCases {
            let object = try JSONSerialization.jsonObject(with: Data(shape.jsonSchema.utf8)) as? [String: Any]
            #expect(object?["type"] as? String == "object", "\(shape)")
        }
    }
}

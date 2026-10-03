import Foundation
import MindMapAICore
import MindMapDomain
import Testing
@testable import LocalLLM

/// Answers with fixed text, so the provider's parsing and checks run without
/// a model.
struct ScriptedEngine: LocalInferenceEngine {
    var answer: String

    func generate(instructions: String, prompt: String, shape: LocalOutputShape, maximumTokens: Int) -> AsyncThrowingStream<String, any Error> {
        let pieces = answer.map(String.init)
        return AsyncThrowingStream { continuation in
            for piece in pieces { continuation.yield(piece) }
            continuation.finish()
        }
    }
}

func temporaryFolder() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "LocalLLMTests-\(UUID().uuidString)", directoryHint: .isDirectory)
}

func model(files: [LocalModel.File], memory: UInt64 = 0) -> LocalModel {
    LocalModel(id: "test-model", displayName: "Test", license: "Apache-2.0", languages: [.english, .vietnamese],
               contextSize: 4_096, minimumPhysicalMemory: memory, files: files)
}

/// A store with the model's one file already in place.
func installedStore(for data: Data) async throws -> (LocalModelStore, LocalModel) {
    let source = temporaryFolder().appending(path: "weights.bin")
    try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: source)
    let file = LocalModel.File(name: "weights.bin", url: source, byteCount: Int64(data.count), sha256: try LocalModelStore.sha256(of: source))
    let store = LocalModelStore(root: temporaryFolder(), fetch: copying, availableCapacity: { _ in nil })
    let model = model(files: [file])
    try await store.install(model)
    return (store, model)
}

let copying: LocalModelStore.Fetch = { url in
    let copy = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.copyItem(at: url, to: copy)
    return copy
}

func context(_ title: String = "Sleep", language: AILanguage = .english) -> AIContext {
    AIContext(mapID: MapID(), mapTitle: "Healthy habits",
              focus: ContextTopic(nodeID: NodeID(), parentID: nil, title: title, depth: 0),
              language: language, userLocaleIdentifier: "en_US")
}

@Suite struct LocalLLMProviderTests {
    @Test func notInstalledIsNotReady() async {
        let store = LocalModelStore(root: temporaryFolder(), fetch: copying, availableCapacity: { _ in nil })
        let provider = LocalLLMProvider(model: model(files: [LocalModel.File(name: "w", url: URL(filePath: "/nonexistent"), byteCount: 1, sha256: "")]),
                                        store: store) { ScriptedEngine(answer: "") }
        #expect(await provider.capabilities().model == .unknown)
        await #expect(throws: AIError.unavailable(.unknown)) {
            try await provider.expandTopic(ExpandTopicRequest(context: context()))
        }
    }

    @Test func tooLittleMemoryIsNotEligible() async throws {
        let (store, installed) = try await installedStore(for: Data("w".utf8))
        var big = installed
        big.minimumPhysicalMemory = 64 << 30
        let provider = LocalLLMProvider(model: big, store: store, physicalMemory: 6 << 30) { ScriptedEngine(answer: "") }
        #expect(await provider.capabilities().model == .deviceNotEligible)
    }

    @Test func expandParsesFencedJSONAndKeepsTheLimit() async throws {
        let (store, model) = try await installedStore(for: Data("w".utf8))
        let answer = """
        ```json
        {"topics": [{"title": "Dark room"}, {"title": "No caffeine after 2 pm"}, {"title": "Wind-down routine"}]}
        ```
        """
        let provider = LocalLLMProvider(model: model, store: store) { ScriptedEngine(answer: answer) }
        let focus = context()
        let proposal = try await provider.expandTopic(ExpandTopicRequest(context: focus, maximumTopics: 2))
        #expect(proposal.anchor == .node(focus.focus.nodeID))
        #expect(proposal.topics.map(\.title) == ["Dark room", "No caffeine after 2 pm"])
    }

    @Test func generateMapSkipsThinkingAndBuildsTheTree() async throws {
        let (store, model) = try await installedStore(for: Data("w".utf8))
        let answer = """
        <think>plan {not json}</think>{"title": "Ôn thi Toán", "topics": [
          {"temporaryID": "t1", "parentTemporaryID": "", "title": "Đại số"},
          {"temporaryID": "t2", "parentTemporaryID": "t1", "title": "Hàm số"}]}
        """
        let provider = LocalLLMProvider(model: model, store: store) { ScriptedEngine(answer: answer) }
        let proposal = try await provider.generateMap(GenerateMapRequest(prompt: "Ôn thi", language: .vietnamese, userLocaleIdentifier: "vi_VN"))
        #expect(proposal.suggestedMapTitle == "Ôn thi Toán")
        #expect(proposal.topics.map(\.parentTemporaryID) == [nil, "t1"])
    }

    @Test func generateMapWithALoopIsInvalid() async throws {
        let (store, model) = try await installedStore(for: Data("w".utf8))
        let answer = #"{"title": "x", "topics": [{"temporaryID": "t1", "parentTemporaryID": "t2", "title": "A"}, {"temporaryID": "t2", "parentTemporaryID": "t1", "title": "B"}]}"#
        let provider = LocalLLMProvider(model: model, store: store) { ScriptedEngine(answer: answer) }
        await #expect(throws: AIError.self) {
            try await provider.generateMap(GenerateMapRequest(prompt: "x", language: .english, userLocaleIdentifier: "en_US"))
        }
    }

    @Test func rewriteDropsTheOriginalAndRepeats() async throws {
        let (store, model) = try await installedStore(for: Data("w".utf8))
        let answer = #"{"titles": ["Sleep", "Better sleep", "better sleep", "Rest well"]}"#
        let provider = LocalLLMProvider(model: model, store: store) { ScriptedEngine(answer: answer) }
        let rewrite = try await provider.rewrite(RewriteRequest(context: context(), style: .clearer))
        #expect(rewrite.suggestions == ["Better sleep", "Rest well"])
    }

    @Test func summaryWithoutJSONIsInvalid() async throws {
        let (store, model) = try await installedStore(for: Data("w".utf8))
        let provider = LocalLLMProvider(model: model, store: store) { ScriptedEngine(answer: "I cannot help with that.") }
        await #expect(throws: AIError.invalidResponse(.empty)) {
            try await provider.summarize(SummarizeRequest(context: context()))
        }
    }

    @Test func brainstormAcceptsPlainStrings() async throws {
        let (store, model) = try await installedStore(for: Data("w".utf8))
        let provider = LocalLLMProvider(model: model, store: store) { ScriptedEngine(answer: #"{"topics": ["Escape room", "Cooking class"]}"#) }
        let proposal = try await provider.brainstorm(BrainstormRequest(context: context()))
        #expect(proposal.topics.map(\.title) == ["Escape room", "Cooking class"])
    }

    @Test func jsonObjectIgnoresBracesInStrings() {
        #expect(LocalAnswer.jsonObject(in: #"x {"summary": "a } b"} y"#) == #"{"summary": "a } b"}"#)
    }
}

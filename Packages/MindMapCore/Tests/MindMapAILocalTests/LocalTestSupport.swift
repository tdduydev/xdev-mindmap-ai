import Foundation
import MindMapAICore
import MindMapDomain
@testable import MindMapAILocal

/// Answers each call with the next scripted text and records the prompts, so
/// the provider's parsing, checks and retry run without a model.
final class ScriptedEngine: LocalInferenceEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [Result<String, any Error>]
    private(set) var prompts: [String] = []
    private(set) var shapes: [LocalOutputShape] = []

    init(_ answers: String...) {
        self.answers = answers.map { .success($0) }
    }

    init(failing error: any Error) {
        answers = [.failure(error)]
    }

    var callCount: Int { lock.withLock { prompts.count } }

    func generate(instructions: String, prompt: String, shape: LocalOutputShape, maximumTokens: Int) -> AsyncThrowingStream<String, any Error> {
        let answer: Result<String, any Error> = lock.withLock {
            prompts.append(prompt)
            shapes.append(shape)
            return answers.count > 1 ? answers.removeFirst() : answers.first ?? .success("")
        }
        return AsyncThrowingStream { continuation in
            switch answer {
            case .success(let text):
                // Piece by piece, as a real engine streams tokens.
                for piece in text.map(String.init) { continuation.yield(piece) }
                continuation.finish()
            case .failure(let error):
                continuation.finish(throwing: error)
            }
        }
    }
}

struct EngineFailure: Error {}

func readyProvider(_ engine: ScriptedEngine, model: LocalModel = .qwen3_1_7B) -> LocalLLMProvider {
    LocalLLMProvider(model: model, isDeviceEligible: true, physicalMemory: 8 << 30,
                     isInstalled: { true }, engine: { engine })
}

func context(_ title: String = "Sleep", language: AILanguage = .english) -> AIContext {
    AIContext(mapID: MapID(), mapTitle: "Healthy habits",
              focus: ContextTopic(nodeID: NodeID(), parentID: nil, title: title, depth: 0),
              language: language, userLocaleIdentifier: language.locale.identifier)
}

// MLX needs Metal on Apple silicon: Intel Macs and the Simulator compile the
// packages but never get here (ADR 0011, decision 6); tests use a fake engine.
#if arch(arm64) && !targetEnvironment(simulator)
import Foundation
import MindMapAILocal
import MLXGuidedGeneration
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Runs a downloaded MLX model with decoding constrained to the answer's JSON
/// Schema (ADR 0011, decision 5), so a small model cannot answer in the wrong
/// shape; `LocalAnswer` still checks every answer.
nonisolated final class MLXInferenceEngine: LocalInferenceEngine {
    private let container: ModelContainer
    private let grammarTokenizer: GrammarTokenizer

    private init(container: ModelContainer, grammarTokenizer: GrammarTokenizer) {
        self.container = container
        self.grammarTokenizer = grammarTokenizer
    }

    /// Loads the weights and tokenizer from a folder in MLX format (config.json,
    /// tokenizer files, safetensors); nothing is downloaded here.
    static func load(from folder: URL) async throws -> MLXInferenceEngine {
        let container = try await LLMModelFactory.shared.loadContainer(from: folder, using: TransformersTokenizerLoader())
        // Built once per model: extracting the vocabulary walks all ~150k tokens.
        let grammarTokenizer = try await container.perform { context in
            let vocabulary = TokenizerVocabExtractor.extractForGrammar(from: context.tokenizer)
            return try GrammarTokenizer(
                vocab: vocabulary.vocab,
                vocabType: vocabulary.vocabType,
                eosTokenId: Int32(context.tokenizer.eosTokenId ?? 0)
            )
        }
        return MLXInferenceEngine(container: container, grammarTokenizer: grammarTokenizer)
    }

    func generate(
        instructions: String,
        prompt: String,
        shape: LocalOutputShape,
        maximumTokens: Int
    ) -> AsyncThrowingStream<String, any Error> {
        stream(instructions: instructions, prompt: prompt, shape: shape, maximumTokens: maximumTokens)
    }

    /// Free text, without a schema: the chat evaluations, whose answer is prose.
    func generateText(instructions: String, prompt: String, maximumTokens: Int) -> AsyncThrowingStream<String, any Error> {
        stream(instructions: instructions, prompt: prompt, shape: nil, maximumTokens: maximumTokens)
    }

    private func stream(
        instructions: String,
        prompt: String,
        shape: LocalOutputShape?,
        maximumTokens: Int
    ) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            // Detached: generation is synchronous and the guided loop compiles the
            // grammar before the first token, which would freeze the window on the main actor.
            let task = Task.detached(priority: .userInitiated) { [container, grammarTokenizer] in
                do {
                    try await container.perform { context in
                        // Qwen3 thinks aloud by default, which spends the token
                        // budget before the JSON starts (same as the benchmark).
                        let input = try await context.processor.prepare(input: UserInput(
                            chat: [.system(instructions), .user(prompt)],
                            additionalContext: ["enable_thinking": false]
                        ))
                        guard let shape else {
                            let generation = try MLXLMCommon.generate(
                                input: input,
                                parameters: GenerateParameters(maxTokens: maximumTokens),
                                context: context
                            )
                            for await item in generation {
                                if case .chunk(let piece) = item { continuation.yield(piece) }
                                if Task.isCancelled { break }
                            }
                            return
                        }
                        let constraint = try GrammarConstraint(
                            tokenizer: grammarTokenizer,
                            jsonSchema: shape.jsonSchema,
                            fastForward: true,
                            hostTokenizer: context.tokenizer
                        )
                        _ = try GuidedGenerationLoop.run(
                            input: input,
                            context: context,
                            constraint: constraint,
                            maxTokens: maximumTokens,
                            vocabSize: grammarTokenizer.vocabSize
                        ) { piece in
                            continuation.yield(piece)
                            return !Task.isCancelled
                        }
                    }
                    try Task.checkCancellation()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Reads tokenizer.json with swift-transformers, the tokenizer mlx-swift-lm
/// expects. Written out instead of `#huggingFaceTokenizerLoader()` so the app
/// does not build swift-syntax for the macro.
private nonisolated struct TransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        TokenizerBridge(try await AutoTokenizer.from(modelFolder: directory))
    }
}

private nonisolated struct TokenizerBridge: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
#endif

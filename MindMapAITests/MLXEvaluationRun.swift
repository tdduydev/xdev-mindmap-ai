#if arch(arm64) && !targetEnvironment(simulator)
import Foundation
@testable import MindMapAI
import MindMapAIEvaluation
import MindMapAILocal
import Testing

/// The MM-105 evaluations through the app's own MLX engine, guided decoding
/// included, instead of `mlx_lm.server`. Opt-in and slow (minutes): run by
/// scripts/evaluations/run-mlx-swift.sh, which sets the variables; skipped in ci.sh.
@Suite("MLX evaluations", .serialized)
struct MLXEvaluationRun {
    /// MINDMAP_MLX_MODEL: a model folder in MLX format; MINDMAP_MLX_EVALUATIONS: the JSONL to write.
    nonisolated static let environment = ProcessInfo.processInfo.environment

    @Test(.enabled(if: environment["MINDMAP_MLX_MODEL"] != nil), .timeLimit(.minutes(30)))
    func allCases() async throws {
        let folder = URL(filePath: try #require(Self.environment["MINDMAP_MLX_MODEL"]))
        let output = URL(filePath: try #require(Self.environment["MINDMAP_MLX_EVALUATIONS"]))
        let name = Self.environment["MINDMAP_MLX_MODEL_NAME"] ?? folder.lastPathComponent
        let engine = try await MLXInferenceEngine.load(from: folder)
        let provider = LocalLLMProvider(model: .qwen3_1_7B, isDeviceEligible: true, isInstalled: { true }, engine: { engine })
        let chat: AIEvaluationChatModel = { instructions, prompt in
            var text = ""
            for try await piece in engine.generateText(instructions: instructions, prompt: prompt, maximumTokens: 600) {
                text += piece
            }
            return Self.withoutThinking(text)
        }

        var lines = Data()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var passed = 0
        for evaluation in AIEvaluationSuite.cases {
            let outcome = await AIEvaluationRunner.run(evaluation, provider: provider, chat: chat)
            lines += try encoder.encode(Line(provider: "mlx-swift/" + name, outcome: outcome)) + Data("\n".utf8)
            if outcome.passed { passed += 1 }
        }
        try lines.write(to: output)
        print("MLX EVAL DONE \(passed)/\(AIEvaluationSuite.cases.count)")
    }

    /// Same shape as `mindmap-ai-eval`'s lines, so summarize.py reads both.
    struct Line: Encodable {
        var provider: String
        var outcome: AIEvaluationOutcome
    }

    /// Qwen3 still writes an empty <think></think> with thinking turned off.
    nonisolated static func withoutThinking(_ text: String) -> String {
        var body = text
        while let open = body.range(of: "<think>") {
            let close = body.range(of: "</think>", range: open.upperBound..<body.endIndex)
            body.removeSubrange(open.lowerBound..<(close?.upperBound ?? body.endIndex))
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif

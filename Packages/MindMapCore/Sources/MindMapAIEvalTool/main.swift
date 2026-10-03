// Runs AIEvaluationSuite on Foundation Models or on a local model and writes
// one JSON line per case (MM-105). A developer tool, never shipped.
//
//   swift run --package-path Packages/MindMapCore mindmap-ai-eval apple OUT.jsonl
//   swift run --package-path Packages/MindMapCore mindmap-ai-eval local OUT.jsonl http://127.0.0.1:8089 MODEL
//
// The local mode talks to `mlx_lm.server` (scripts/evaluations/run-local.sh)
// through MLXServerEngine, so the real LocalLLMProvider parses, checks and
// retries every answer, with the same PromptCatalog as the app.
import Foundation
import FoundationModels
import MindMapAIApple
import MindMapAICore
import MindMapAIEvaluation
import MindMapAILocal

let arguments = CommandLine.arguments
guard arguments.count >= 3, ["apple", "local"].contains(arguments[1]) else {
    print("usage: mindmap-ai-eval apple|local OUT.jsonl [SERVER-URL MODEL]")
    exit(2)
}
let mode = arguments[1]
let output = URL(filePath: arguments[2])

let provider: any AIProvider
let chat: AIEvaluationChatModel
let engine: MLXServerEngine?
switch mode {
case "apple":
    provider = AppleFoundationModelProvider()
    engine = nil
    chat = { instructions, prompt in
        let session = LanguageModelSession(instructions: instructions)
        return try await session.respond(to: prompt).content
    }
default:
    guard arguments.count >= 5, let url = URL(string: arguments[3]) else {
        print("local needs SERVER-URL and MODEL")
        exit(2)
    }
    let server = MLXServerEngine(baseURL: url, model: arguments[4])
    engine = server
    provider = LocalLLMProvider(model: .qwen3_1_7B, isDeviceEligible: true, physicalMemory: ProcessInfo.processInfo.physicalMemory,
                                isInstalled: { true }, engine: { server })
    chat = { instructions, prompt in
        var text = ""
        for try await piece in server.generate(instructions: instructions, prompt: prompt, shape: nil, maximumTokens: 600) {
            text += piece
        }
        return LocalTextCleanup.withoutThinking(text)
    }
}

let capabilities = await provider.capabilities()
print("model:", capabilities.model.rawValue, "languages:", capabilities.supportedLanguages.map(\.rawValue).sorted())
FileManager.default.createFile(atPath: output.path, contents: nil)
let handle = try FileHandle(forWritingTo: output)
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

struct Line: Encodable {
    var provider: String
    var outcome: AIEvaluationOutcome
    var completionTokens: Int?
    var generationSeconds: Double?
}

let only = ProcessInfo.processInfo.environment["ONLY"]
var passed = 0
var total = 0
for evaluation in AIEvaluationSuite.cases where only.map({ evaluation.id.hasPrefix($0) }) ?? true {
    await engine?.resetStatistics()
    let outcome = await AIEvaluationRunner.run(evaluation, provider: provider, chat: chat)
    let statistics = await engine?.statistics
    let line = Line(provider: mode == "apple" ? "foundation-models" : arguments[4], outcome: outcome,
                    completionTokens: statistics?.completionTokens, generationSeconds: statistics?.seconds)
    handle.write(try encoder.encode(line) + Data("\n".utf8))
    total += 1
    if outcome.passed { passed += 1 }
    print(outcome.passed ? "PASS" : "FAIL", outcome.id, String(format: "%.1fs", outcome.seconds), outcome.reason ?? "")
}
try handle.close()
print("EVAL DONE \(passed)/\(total)")

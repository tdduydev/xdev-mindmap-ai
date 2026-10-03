import Foundation
import MindMapAILocal

/// A `LocalInferenceEngine` backed by `mlx_lm.server`'s OpenAI-style endpoint,
/// so evaluations run the same MLX weights as the app without building the
/// app. It cannot constrain decoding, so its pass rates are a lower bound for
/// the app's, which decodes against the schema.
actor MLXServerEngine: LocalInferenceEngine {
    struct Statistics: Sendable { var completionTokens = 0; var seconds = 0.0 }

    let baseURL: URL
    let model: String
    private(set) var statistics = Statistics()

    init(baseURL: URL, model: String) {
        self.baseURL = baseURL
        self.model = model
    }

    func resetStatistics() { statistics = Statistics() }

    private func record(tokens: Int, seconds: Double) {
        statistics.completionTokens += tokens
        statistics.seconds += seconds
    }

    nonisolated func generate(instructions: String, prompt: String, shape: LocalOutputShape, maximumTokens: Int) -> AsyncThrowingStream<String, any Error> {
        generate(instructions: instructions, prompt: prompt, shape: Optional(shape), maximumTokens: maximumTokens)
    }

    nonisolated func generate(instructions: String, prompt: String, shape: LocalOutputShape?, maximumTokens: Int) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(try await self.complete(instructions: instructions, prompt: prompt, maximumTokens: maximumTokens))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func complete(instructions: String, prompt: String, maximumTokens: Int) async throws -> String {
        var request = URLRequest(url: baseURL.appending(path: "v1/chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "system", "content": instructions], ["role": "user", "content": prompt]],
            "max_tokens": maximumTokens,
            "temperature": 0.3,
            // Qwen3 thinks first by default, doubling the wait for no gain on
            // short JSON (MM-77); the app passes enable_thinking=false.
            "chat_template_kwargs": ["enable_thinking": false],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let clock = ContinuousClock()
        let start = clock.now
        let (data, _) = try await URLSession.shared.data(for: request)
        let elapsed = start.duration(to: clock.now)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        guard let text = message?["content"] as? String else { throw URLError(.cannotParseResponse) }
        let usage = json?["usage"] as? [String: Any]
        record(tokens: usage?["completion_tokens"] as? Int ?? 0,
               seconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
        return text
    }
}

enum LocalTextCleanup {
    static func withoutThinking(_ text: String) -> String {
        var body = text
        while let open = body.range(of: "<think>") {
            let close = body.range(of: "</think>", range: open.upperBound..<body.endIndex)
            body.removeSubrange(open.lowerBound..<(close?.upperBound ?? body.endIndex))
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

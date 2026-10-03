import Foundation

/// The shape an answer must have. An engine that can constrain decoding
/// (llama.cpp GBNF from `jsonSchema`) uses it; one that cannot relies on the
/// instruction and `LocalAnswer` parsing the text.
public enum LocalOutputShape: String, Hashable, Sendable {
    case mindMap, topicList, rewrites, summary

    public var jsonSchema: String {
        switch self {
        case .mindMap:
            #"{"type":"object","properties":{"title":{"type":"string"},"topics":{"type":"array","maxItems":30,"items":{"type":"object","properties":{"temporaryID":{"type":"string"},"parentTemporaryID":{"type":"string"},"title":{"type":"string"}},"required":["temporaryID","parentTemporaryID","title"]}}},"required":["title","topics"]}"#
        case .topicList:
            #"{"type":"object","properties":{"topics":{"type":"array","maxItems":12,"items":{"type":"object","properties":{"title":{"type":"string"}},"required":["title"]}}},"required":["topics"]}"#
        case .rewrites:
            #"{"type":"object","properties":{"titles":{"type":"array","maxItems":3,"items":{"type":"string"}}},"required":["titles"]}"#
        case .summary:
            #"{"type":"object","properties":{"summary":{"type":"string"}},"required":["summary"]}"#
        }
    }

    /// The line added to the instructions, the same in the benchmark script.
    public var instruction: String {
        let shape = switch self {
        case .mindMap: #"{"title": string, "topics": [{"temporaryID": string, "parentTemporaryID": string, "title": string}]}"#
        case .topicList: #"{"topics": [{"title": string}]}"#
        case .rewrites: #"{"titles": [string]}"#
        case .summary: #"{"summary": string}"#
        }
        return "Answer with JSON only, no Markdown, matching: " + shape
    }
}

/// A local runtime with a model loaded. The MLX and llama.cpp adapters live
/// outside main (docs/research/local-llm.md) so main has no external package.
public protocol LocalInferenceEngine: Sendable {
    /// Streams text pieces. Cancelling the consuming task stops decoding.
    func generate(
        instructions: String,
        prompt: String,
        shape: LocalOutputShape,
        maximumTokens: Int
    ) -> AsyncThrowingStream<String, any Error>
}

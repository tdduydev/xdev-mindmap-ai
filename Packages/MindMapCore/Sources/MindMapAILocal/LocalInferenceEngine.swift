import Foundation

/// The shape an answer must have. The MLX engine constrains decoding with
/// `jsonSchema`; an engine that cannot relies on the instruction, and every
/// answer is checked against the shape again by `LocalAnswer` either way.
public enum LocalOutputShape: String, Hashable, Sendable, CaseIterable {
    case mindMap, topicList, rewrites, summary, tags, groups, title

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
        case .tags:
            #"{"type":"object","properties":{"topics":{"type":"array","maxItems":12,"items":{"type":"object","properties":{"reference":{"type":"string"},"tags":{"type":"array","maxItems":3,"items":{"type":"string"}}},"required":["reference","tags"]}}},"required":["topics"]}"#
        case .groups:
            #"{"type":"object","properties":{"groups":{"type":"array","maxItems":5,"items":{"type":"object","properties":{"title":{"type":"string"},"references":{"type":"array","items":{"type":"string"}}},"required":["title","references"]}}},"required":["groups"]}"#
        case .title:
            #"{"type":"object","properties":{"title":{"type":"string"}},"required":["title"]}"#
        }
    }

    /// The line added to the instructions, the same in the benchmark script.
    public var instruction: String {
        let shape = switch self {
        case .mindMap: #"{"title": string, "topics": [{"temporaryID": string, "parentTemporaryID": string, "title": string}]}"#
        case .topicList: #"{"topics": [{"title": string}]}"#
        case .rewrites: #"{"titles": [string]}"#
        case .summary: #"{"summary": string}"#
        case .tags: #"{"topics": [{"reference": string, "tags": [string]}]}"#
        case .groups: #"{"groups": [{"title": string, "references": [string]}]}"#
        case .title: #"{"title": string}"#
        }
        return "Answer with JSON only, no Markdown, matching: " + shape
    }
}

/// A local runtime with a model loaded. MLX lives in the app target behind this
/// protocol (ADR 0011), so MindMapCore and `swift test` never link it.
public protocol LocalInferenceEngine: Sendable {
    /// Streams text pieces. Cancelling the consuming task stops decoding.
    func generate(
        instructions: String,
        prompt: String,
        shape: LocalOutputShape,
        maximumTokens: Int
    ) -> AsyncThrowingStream<String, any Error>
}

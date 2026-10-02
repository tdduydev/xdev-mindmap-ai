import Foundation
import MindMapAICore
import MindMapDomain
import Synchronization

/// An `AIProvider` that answers from a script, for tests and previews.
///
/// Queue answers per feature with `enqueue`; each request takes the next one,
/// or fails with `AIError.generationFailed` when the queue is empty. Like the
/// real provider it refuses requests the capabilities do not allow, and it
/// records every request so tests can check the context that was sent.
public final class MockAIProvider: AIProvider {
    public enum Answer: Sendable {
        case proposal(AIProposal)
        case rewrite(AIRewrite)
        case summary(AISummary)
        case failure(AIError)
    }

    public enum Request: Hashable, Sendable {
        case generateMap(GenerateMapRequest)
        case expandTopic(ExpandTopicRequest)
        case brainstorm(BrainstormRequest)
        case rewrite(RewriteRequest)
        case summarize(SummarizeRequest)
        case findMissingTopics(MissingTopicsRequest)
    }

    private struct State {
        var capabilities: AICapabilities
        var answers: [AIFeature: [Answer]] = [:]
        var requests: [Request] = []
    }

    private let state: Mutex<State>

    public init(capabilities: AICapabilities = .readyForTesting) {
        state = Mutex(State(capabilities: capabilities))
    }

    public func setCapabilities(_ capabilities: AICapabilities) {
        state.withLock { $0.capabilities = capabilities }
    }

    public func enqueue(_ answer: Answer, for feature: AIFeature) {
        state.withLock { $0.answers[feature, default: []].append(answer) }
    }

    public var requests: [Request] {
        state.withLock { $0.requests }
    }

    // MARK: AIProvider

    public func capabilities() async -> AICapabilities {
        state.withLock { $0.capabilities }
    }

    public func generateMap(_ request: GenerateMapRequest) async throws -> AIProposal {
        try proposal(from: next(.generateMap, language: request.language, recording: .generateMap(request)))
    }

    public func expandTopic(_ request: ExpandTopicRequest) async throws -> AIProposal {
        try proposal(from: next(.expandTopic, language: request.context.language, recording: .expandTopic(request)))
    }

    public func brainstorm(_ request: BrainstormRequest) async throws -> AIProposal {
        try proposal(from: next(.brainstorm, language: request.context.language, recording: .brainstorm(request)))
    }

    public func findMissingTopics(_ request: MissingTopicsRequest) async throws -> AIProposal {
        try proposal(
            from: next(.findMissingTopics, language: request.context.language, recording: .findMissingTopics(request))
        )
    }

    public func rewrite(_ request: RewriteRequest) async throws -> AIRewrite {
        let answer = try next(.rewrite, language: request.outputLanguage, recording: .rewrite(request))
        guard case .rewrite(let rewrite) = answer else { throw AIError.generationFailed }
        return rewrite
    }

    public func summarize(_ request: SummarizeRequest) async throws -> AISummary {
        let answer = try next(.summarize, language: request.context.language, recording: .summarize(request))
        guard case .summary(let summary) = answer else { throw AIError.generationFailed }
        return summary
    }

    // MARK: Script

    private func next(_ feature: AIFeature, language: AILanguage, recording request: Request) throws -> Answer {
        let answer: Answer? = state.withLock { current in
            current.requests.append(request)
            let status = current.capabilities.availability(for: feature, in: language)
            guard status == .ready else { return Answer.failure(.unavailable(status)) }
            guard var queue = current.answers[feature], !queue.isEmpty else { return nil }
            let first = queue.removeFirst()
            current.answers[feature] = queue
            return first
        }
        switch answer {
        case .failure(let error)?: throw error
        case let answer?: return answer
        case nil: throw AIError.generationFailed
        }
    }

    private func proposal(from answer: Answer) throws -> AIProposal {
        guard case .proposal(let proposal) = answer else { throw AIError.generationFailed }
        return proposal
    }
}

extension AICapabilities {
    /// Ready in English and Vietnamese with the context size measured on the
    /// development Mac.
    public static let readyForTesting = AICapabilities(
        model: .ready,
        supportedLanguages: Set(AILanguage.allCases),
        contextSize: AIContextLimits.assumedContextSize
    )
}

extension AIProposal {
    /// Flat suggestions under `nodeID`, with temporary IDs s1, s2…
    public static func suggestions(_ titles: [String], under nodeID: NodeID, feature: AIFeature = .expandTopic) -> AIProposal {
        AIProposal(
            feature: feature,
            anchor: .node(nodeID),
            topics: titles.enumerated().map { ProposedTopic(temporaryID: "s\($0.offset + 1)", title: $0.element) }
        )
    }
}

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
        case tags(AITagSuggestions)
        case failure(AIError)
        /// Partial proposals streamed before the last, complete one.
        case stream([AIProposal])
        /// Never answers; the request ends only when its task is cancelled.
        case hang
    }

    public enum Request: Hashable, Sendable {
        case generateMap(GenerateMapRequest)
        case expandTopic(ExpandTopicRequest)
        case brainstorm(BrainstormRequest)
        case rewrite(RewriteRequest)
        case summarize(SummarizeRequest)
        case findMissingTopics(MissingTopicsRequest)
        case suggestTags(SuggestTagsRequest)
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
        try proposal(from: await waitingNext(.generateMap, language: request.language, recording: .generateMap(request)))
    }

    public func expandTopic(_ request: ExpandTopicRequest) async throws -> AIProposal {
        try proposal(from: await waitingNext(.expandTopic, language: request.context.language, recording: .expandTopic(request)))
    }

    public func brainstorm(_ request: BrainstormRequest) async throws -> AIProposal {
        try proposal(from: await waitingNext(.brainstorm, language: request.context.language, recording: .brainstorm(request)))
    }

    public func findMissingTopics(_ request: MissingTopicsRequest) async throws -> AIProposal {
        try proposal(
            from: await waitingNext(.findMissingTopics, language: request.context.language, recording: .findMissingTopics(request))
        )
    }

    public func rewrite(_ request: RewriteRequest) async throws -> AIRewrite {
        let answer = try await waitingNext(.rewrite, language: request.outputLanguage, recording: .rewrite(request))
        guard case .rewrite(let rewrite) = answer else { throw AIError.generationFailed }
        return rewrite
    }

    public func summarize(_ request: SummarizeRequest) async throws -> AISummary {
        let answer = try await waitingNext(.summarize, language: request.context.language, recording: .summarize(request))
        guard case .summary(let summary) = answer else { throw AIError.generationFailed }
        return summary
    }

    public func suggestTags(_ request: SuggestTagsRequest) async throws -> AITagSuggestions {
        let answer = try await waitingNext(.suggestTags, language: request.language, recording: .suggestTags(request))
        guard case .tags(let tags) = answer else { throw AIError.generationFailed }
        return tags
    }

    public func streamSuggestions(_ request: SuggestionRequest) -> AsyncThrowingStream<ProposalSnapshot, any Error> {
        let recorded: Request = switch request {
        case .generateMap(let request): .generateMap(request)
        case .expandTopic(let request): .expandTopic(request)
        case .brainstorm(let request): .brainstorm(request)
        case .findMissingTopics(let request): .findMissingTopics(request)
        }
        let answer = Result { try next(request.feature, language: request.language, recording: recorded) }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    switch try answer.get() {
                    case .stream(let proposals):
                        for (index, proposal) in proposals.enumerated() {
                            try Task.checkCancellation()
                            continuation.yield(ProposalSnapshot(proposal: proposal, isComplete: index == proposals.count - 1))
                            await Task.yield()
                        }
                    case .hang:
                        try await Task.sleep(for: .seconds(3_600))
                    case let other:
                        continuation.yield(ProposalSnapshot(proposal: try proposal(from: other), isComplete: true))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Script

    /// `next`, where a `.hang` answer waits until the task is cancelled.
    private func waitingNext(_ feature: AIFeature, language: AILanguage, recording request: Request) async throws -> Answer {
        let answer = try next(feature, language: language, recording: request)
        if case .hang = answer {
            try await Task.sleep(for: .seconds(3_600))
            throw CancellationError()
        }
        return answer
    }

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
        switch answer {
        case .proposal(let proposal): return proposal
        case .stream(let proposals): return try proposals.last ?? { throw AIError.generationFailed }()
        default: throw AIError.generationFailed
        }
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

extension AITagSuggestions {
    /// Names per topic, unchecked, as a test scripts them.
    public static func tags(_ names: [NodeID: [String]], order: [NodeID]) -> AITagSuggestions {
        AITagSuggestions(entries: order.map { Entry(nodeID: $0, names: names[$0] ?? []) })
    }
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

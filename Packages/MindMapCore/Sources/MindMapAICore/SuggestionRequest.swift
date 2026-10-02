import Foundation

/// The requests whose answer is a set of suggested topics, which the preview
/// streams onto the canvas.
public enum SuggestionRequest: Hashable, Sendable {
    case generateMap(GenerateMapRequest)
    case expandTopic(ExpandTopicRequest)
    case brainstorm(BrainstormRequest)
    case findMissingTopics(MissingTopicsRequest)

    public var feature: AIFeature {
        switch self {
        case .generateMap: .generateMap
        case .expandTopic: .expandTopic
        case .brainstorm: .brainstorm
        case .findMissingTopics: .findMissingTopics
        }
    }

    public var language: AILanguage {
        switch self {
        case .generateMap(let request): request.language
        case .expandTopic(let request): request.context.language
        case .brainstorm(let request): request.context.language
        case .findMissingTopics(let request): request.context.language
        }
    }
}

/// One step of a streamed proposal.
public struct ProposalSnapshot: Hashable, Sendable {
    public var proposal: AIProposal
    /// True for the last snapshot, which passed `ProposalTranslator` checks and
    /// holds no more topics than the request asked for. Earlier snapshots may
    /// end in a half-written title.
    public var isComplete: Bool

    public init(proposal: AIProposal, isComplete: Bool) {
        self.proposal = proposal
        self.isComplete = isComplete
    }
}

extension AIProvider {
    /// The one-shot answer to a suggestion request.
    public func suggest(_ request: SuggestionRequest) async throws -> AIProposal {
        switch request {
        case .generateMap(let request): try await generateMap(request)
        case .expandTopic(let request): try await expandTopic(request)
        case .brainstorm(let request): try await brainstorm(request)
        case .findMissingTopics(let request): try await findMissingTopics(request)
        }
    }

    /// For providers that cannot stream: the whole answer as one complete snapshot.
    public func streamSuggestions(_ request: SuggestionRequest) -> AsyncThrowingStream<ProposalSnapshot, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let proposal = try await suggest(request)
                    continuation.yield(ProposalSnapshot(proposal: proposal, isComplete: true))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

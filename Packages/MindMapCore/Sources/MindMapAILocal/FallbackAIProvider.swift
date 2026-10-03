import Foundation
import MindMapAICore

/// Which provider answers (ADR 0011, decision 1): Foundation Models wherever
/// it is ready, the downloaded model where Apple Intelligence cannot run, is
/// off, or does not speak the request's language, and otherwise Foundation
/// Models' own state, so the app looks as it did before the fallback existed.
public enum AIProviderChoice: Hashable, Sendable {
    case apple
    case local

    /// Apple's states the local model stands in for. `modelDownloading` is
    /// not one: Apple Intelligence will be ready soon and is the better model.
    /// `unknown` is, since regions without Apple Intelligence report it.
    static let replaceableStates: Set<AIAvailability> = [.deviceNotEligible, .appleIntelligenceOff, .unknown]

    /// The provider for the whole app: what `capabilities()` reports.
    public static func choose(apple: AICapabilities, local: AICapabilities) -> AIProviderChoice {
        guard apple.model != .ready, local.model == .ready, replaceableStates.contains(apple.model) else { return .apple }
        return .local
    }

    /// The provider for one request: as `choose(apple:local:)`, and also the
    /// local model when Foundation Models is ready but not in this language.
    public static func choose(apple: AICapabilities, local: AICapabilities, feature: AIFeature, language: AILanguage) -> AIProviderChoice {
        if apple.availability(for: feature, in: language) == .languageUnsupported,
           local.availability(for: feature, in: language) == .ready {
            return .local
        }
        return choose(apple: apple, local: local)
    }
}

/// One `AIProvider` for the app that sends each request to Foundation Models
/// or the local model by `AIProviderChoice`. Both are asked for capabilities
/// on every request, which is cheap: neither loads a model to answer.
public struct FallbackAIProvider: AIProvider {
    let apple: any AIProvider
    let local: any AIProvider

    public init(apple: any AIProvider, local: any AIProvider) {
        self.apple = apple
        self.local = local
    }

    public func capabilities() async -> AICapabilities {
        let (apple, local) = await (self.apple.capabilities(), self.local.capabilities())
        switch AIProviderChoice.choose(apple: apple, local: local) {
        case .local:
            return local
        case .apple:
            guard apple.model == .ready, local.model == .ready else { return apple }
            // Languages Apple lacks are answered by the local model.
            return AICapabilities(model: .ready, supportedLanguages: apple.supportedLanguages.union(local.supportedLanguages),
                                  contextSize: apple.contextSize)
        }
    }

    /// The provider that answers `feature` in `language` right now.
    public func provider(for feature: AIFeature, in language: AILanguage) async -> any AIProvider {
        let (apple, local) = await (self.apple.capabilities(), self.local.capabilities())
        return switch AIProviderChoice.choose(apple: apple, local: local, feature: feature, language: language) {
        case .apple: self.apple
        case .local: self.local
        }
    }

    public func generateMap(_ request: GenerateMapRequest) async throws -> AIProposal {
        try await provider(for: .generateMap, in: request.language).generateMap(request)
    }

    public func expandTopic(_ request: ExpandTopicRequest) async throws -> AIProposal {
        try await provider(for: .expandTopic, in: request.context.language).expandTopic(request)
    }

    public func brainstorm(_ request: BrainstormRequest) async throws -> AIProposal {
        try await provider(for: .brainstorm, in: request.context.language).brainstorm(request)
    }

    public func rewrite(_ request: RewriteRequest) async throws -> AIRewrite {
        try await provider(for: .rewrite, in: request.outputLanguage).rewrite(request)
    }

    public func summarize(_ request: SummarizeRequest) async throws -> AISummary {
        try await provider(for: .summarize, in: request.context.language).summarize(request)
    }

    public func findMissingTopics(_ request: MissingTopicsRequest) async throws -> AIProposal {
        try await provider(for: .findMissingTopics, in: request.context.language).findMissingTopics(request)
    }

    public func suggestTags(_ request: SuggestTagsRequest) async throws -> AITagSuggestions {
        try await provider(for: .suggestTags, in: request.language).suggestTags(request)
    }

    public func suggestGroups(_ request: SuggestGroupsRequest) async throws -> AIGroupSuggestions {
        try await provider(for: .suggestGroups, in: request.language).suggestGroups(request)
    }

    public func summarizeBoundary(_ request: SummarizeBoundaryRequest) async throws -> AIBoundaryTitle {
        try await provider(for: .summarizeBoundary, in: request.language).summarizeBoundary(request)
    }

    public func streamSuggestions(_ request: SuggestionRequest) -> AsyncThrowingStream<ProposalSnapshot, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let provider = await provider(for: request.feature, in: request.language)
                    for try await snapshot in provider.streamSuggestions(request) {
                        continuation.yield(snapshot)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

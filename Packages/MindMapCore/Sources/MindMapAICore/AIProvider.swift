import Foundation

/// A source of AI suggestions. It only proposes: nothing it returns touches the
/// graph or storage until `ProposalTranslator` turns an accepted proposal into
/// a command.
///
/// Requests run off the main actor, can be cancelled with their task, and
/// throw `AIError` (or `CancellationError`). Implementations load their model
/// on first use, never at launch.
public protocol AIProvider: Sendable {
    /// Checked again whenever the app becomes active.
    func capabilities() async -> AICapabilities

    func generateMap(_ request: GenerateMapRequest) async throws -> AIProposal
    func expandTopic(_ request: ExpandTopicRequest) async throws -> AIProposal
    func brainstorm(_ request: BrainstormRequest) async throws -> AIProposal
    func rewrite(_ request: RewriteRequest) async throws -> AIRewrite
    func summarize(_ request: SummarizeRequest) async throws -> AISummary
    func findMissingTopics(_ request: MissingTopicsRequest) async throws -> AIProposal
    func suggestTags(_ request: SuggestTagsRequest) async throws -> AITagSuggestions
    func suggestGroups(_ request: SuggestGroupsRequest) async throws -> AIGroupSuggestions
    func summarizeBoundary(_ request: SummarizeBoundaryRequest) async throws -> AIBoundaryTitle

    /// The answer to a suggestion request as it is written, so the preview can
    /// show the first topics within seconds (NFR-PERF-07). The last snapshot is
    /// complete and checked; earlier ones are for display only. Cancelling the
    /// consuming task cancels the request. A default runs the one-shot method
    /// and yields once.
    func streamSuggestions(_ request: SuggestionRequest) -> AsyncThrowingStream<ProposalSnapshot, any Error>
}

/// Why an AI request produced nothing. Each case maps to one calm message in
/// the UI (FR-AI-14); none of them means the map changed.
public enum AIError: Error, Hashable, Sendable {
    /// The feature cannot run on this device right now.
    case unavailable(AIAvailability)
    /// The model's safety guardrails blocked the request or the answer. The app
    /// suggests rephrasing and never rewrites the prompt to get around it.
    case guardrailViolation
    case refusal
    /// The request did not fit the context window; a smaller branch may.
    case contextSizeExceeded
    case unsupportedLanguage
    case rateLimited
    /// The answer arrived but did not form a usable proposal.
    case invalidResponse(ProposalError)
    case generationFailed

    /// A name safe to log: no map content, no model output.
    public var logName: String {
        switch self {
        case .unavailable(let availability): "unavailable.\(availability.rawValue)"
        case .guardrailViolation: "guardrailViolation"
        case .refusal: "refusal"
        case .contextSizeExceeded: "contextSizeExceeded"
        case .unsupportedLanguage: "unsupportedLanguage"
        case .rateLimited: "rateLimited"
        case .invalidResponse: "invalidResponse"
        case .generationFailed: "generationFailed"
        }
    }
}

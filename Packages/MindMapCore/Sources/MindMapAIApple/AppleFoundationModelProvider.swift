import Foundation
import FoundationModels
import MindMapAICore
import os

/// The on-device Apple Intelligence model behind `AIProvider`.
///
/// Only `SystemLanguageModel` is used: Private Cloud Compute runs on Apple's
/// servers, which the privacy promise rules out (ADR 0001, FR-AI-16). Each
/// request opens its own short session, so nothing loads before the first
/// request and no earlier request eats into the next one's context window.
public struct AppleFoundationModelProvider: AIProvider {
    private static let logger = Logger(subsystem: "asia.xdev.mindmapai", category: "AI")

    public let catalog: PromptCatalog

    public init(catalog: PromptCatalog = PromptCatalog()) {
        self.catalog = catalog
    }

    public func capabilities() async -> AICapabilities {
        AppleCapabilityProbe.current()
    }

    public func generateMap(_ request: GenerateMapRequest) async throws -> AIProposal {
        let generated = try await respond(
            .generateMap,
            language: request.language,
            userLocaleIdentifier: request.userLocaleIdentifier,
            prompt: catalog.prompt(for: request),
            generating: GeneratedMindMap.self
        )
        return try checked(generated.proposal(), feature: .generateMap)
    }

    public func expandTopic(_ request: ExpandTopicRequest) async throws -> AIProposal {
        let context = request.context
        let generated = try await respond(
            .expandTopic,
            language: context.language,
            userLocaleIdentifier: context.userLocaleIdentifier,
            prompt: catalog.prompt(for: request),
            generating: GeneratedTopicList.self
        )
        let proposal = generated.proposal(for: .expandTopic, anchor: .node(context.focus.nodeID), limit: request.maximumTopics)
        return try checked(proposal, feature: .expandTopic)
    }

    public func brainstorm(_ request: BrainstormRequest) async throws -> AIProposal {
        let context = request.context
        let generated = try await respond(
            .brainstorm,
            language: context.language,
            userLocaleIdentifier: context.userLocaleIdentifier,
            prompt: catalog.prompt(for: request),
            generating: GeneratedTopicList.self
        )
        let proposal = generated.proposal(for: .brainstorm, anchor: .node(context.focus.nodeID), limit: request.maximumTopics)
        return try checked(proposal, feature: .brainstorm)
    }

    public func findMissingTopics(_ request: MissingTopicsRequest) async throws -> AIProposal {
        let context = request.context
        let generated = try await respond(
            .findMissingTopics,
            language: context.language,
            userLocaleIdentifier: context.userLocaleIdentifier,
            prompt: catalog.prompt(for: request),
            generating: GeneratedTopicList.self
        )
        let proposal = generated.proposal(for: .findMissingTopics, anchor: .node(context.focus.nodeID), limit: request.maximumTopics)
        return try checked(proposal, feature: .findMissingTopics)
    }

    public func rewrite(_ request: RewriteRequest) async throws -> AIRewrite {
        let context = request.context
        let generated = try await respond(
            .rewrite,
            language: request.outputLanguage,
            userLocaleIdentifier: context.userLocaleIdentifier,
            prompt: catalog.prompt(for: request),
            generating: GeneratedRewrites.self
        )
        let original = context.focus.title
        var seen: Set<String> = [original.lowercased()]
        let suggestions = generated.titles
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        guard !suggestions.isEmpty else { throw failure(.invalidResponse(.empty), feature: .rewrite) }
        return AIRewrite(nodeID: context.focus.nodeID, originalTitle: original, suggestions: suggestions)
    }

    public func summarize(_ request: SummarizeRequest) async throws -> AISummary {
        let context = request.context
        try await requireReady(.summarize, language: context.language)
        let session = makeSession(for: .summarize, language: context.language, userLocaleIdentifier: context.userLocaleIdentifier)
        let text: String
        do {
            text = try await session.respond(to: catalog.prompt(for: request)).content
        } catch {
            throw mapped(error, feature: .summarize)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw failure(.invalidResponse(.empty), feature: .summarize) }
        return AISummary(nodeID: context.focus.nodeID, text: trimmed, isPartial: context.isTruncated)
    }

    // MARK: Plumbing

    private func respond<Content: Generable>(
        _ feature: AIFeature,
        language: AILanguage,
        userLocaleIdentifier: String,
        prompt: String,
        generating type: Content.Type
    ) async throws -> Content {
        try await requireReady(feature, language: language)
        let session = makeSession(for: feature, language: language, userLocaleIdentifier: userLocaleIdentifier)
        do {
            return try await session.respond(to: prompt, generating: type).content
        } catch {
            throw mapped(error, feature: feature)
        }
    }

    private func requireReady(_ feature: AIFeature, language: AILanguage) async throws {
        let status = await capabilities().availability(for: feature, in: language)
        guard status == .ready else { throw failure(.unavailable(status), feature: feature) }
    }

    private func makeSession(for feature: AIFeature, language: AILanguage, userLocaleIdentifier: String) -> LanguageModelSession {
        // Rewriting and summarizing transform the person's own text, which
        // Apple's permissive guardrails are meant for. Generating new content
        // keeps the default guardrails.
        let guardrails: SystemLanguageModel.Guardrails = switch feature {
        case .rewrite, .summarize: .permissiveContentTransformations
        case .generateMap, .expandTopic, .brainstorm, .findMissingTopics: .default
        }
        let model = SystemLanguageModel(guardrails: guardrails)
        let instructions = catalog.instructions(for: feature, language: language, userLocaleIdentifier: userLocaleIdentifier)
        return LanguageModelSession(model: model, instructions: instructions)
    }

    /// Runs the translator's checks before the proposal leaves the provider, so
    /// a malformed answer surfaces as `invalidResponse` right away.
    private func checked(_ proposal: AIProposal, feature: AIFeature) throws -> AIProposal {
        do {
            _ = try ProposalTranslator.validate(proposal)
            return proposal
        } catch let error as ProposalError {
            throw failure(.invalidResponse(error), feature: feature)
        }
    }

    private func mapped(_ error: any Error, feature: AIFeature) -> any Error {
        if error is CancellationError { return error }
        guard let generationError = error as? LanguageModelSession.GenerationError else {
            return failure(.generationFailed, feature: feature)
        }
        let aiError: AIError
        if case .guardrailViolation = generationError {
            aiError = .guardrailViolation
        } else if case .refusal = generationError {
            aiError = .refusal
        } else if case .exceededContextWindowSize = generationError {
            aiError = .contextSizeExceeded
        } else if case .unsupportedLanguageOrLocale = generationError {
            aiError = .unsupportedLanguage
        } else if case .rateLimited = generationError {
            aiError = .rateLimited
        } else if case .assetsUnavailable = generationError {
            aiError = .unavailable(.modelDownloading)
        } else {
            aiError = .generationFailed
        }
        return failure(aiError, feature: feature)
    }

    /// Logs the kind of failure only: prompts and answers hold map content.
    private func failure(_ error: AIError, feature: AIFeature) -> AIError {
        Self.logger.error("AI \(feature.rawValue, privacy: .public) failed: \(error.logName, privacy: .public)")
        return error
    }
}

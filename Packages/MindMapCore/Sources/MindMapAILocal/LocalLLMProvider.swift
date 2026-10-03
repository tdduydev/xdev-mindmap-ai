import Foundation
import MindMapAIApple
import MindMapAICore
import MindMapDomain
import OSLog

/// The fallback provider (ADR 0011): the same prompts as Foundation Models
/// (`PromptCatalog`), sent to a downloaded open model. Every answer is parsed
/// against its JSON shape and checked by the same functions as the Apple
/// provider's (`ProposalTranslator`, `AITagSuggestions.checked`…); an answer
/// that fails is asked for again, and one that fails twice is
/// `invalidResponse`. Nothing it returns is applied without Accept.
///
/// Suggestions arrive as one snapshot (the default `streamSuggestions`).
public struct LocalLLMProvider: AIProvider {
    public let model: LocalModel
    let isDeviceEligible: Bool
    let isInstalled: @Sendable () async -> Bool
    let engine: @Sendable () async throws -> any LocalInferenceEngine
    let physicalMemory: UInt64
    let catalog: PromptCatalog
    /// Two tries: constrained decoding makes a bad shape rare, and a third
    /// try costs another full answer's wait on an iPhone.
    public static let maximumAttempts = 2

    private static let logger = Logger(subsystem: "asia.xdev.mindmapai", category: "LocalLLM")

    /// `engine` loads the model on first use, never at launch.
    public init(
        model: LocalModel,
        isDeviceEligible: Bool = LocalDeviceEligibility.current,
        physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory,
        catalog: PromptCatalog = PromptCatalog(),
        isInstalled: @escaping @Sendable () async -> Bool,
        engine: @escaping @Sendable () async throws -> any LocalInferenceEngine
    ) {
        self.model = model
        self.isDeviceEligible = isDeviceEligible
        self.physicalMemory = physicalMemory
        self.catalog = catalog
        self.isInstalled = isInstalled
        self.engine = engine
    }

    public func capabilities() async -> AICapabilities {
        #if arch(x86_64)
        // MLX needs Apple silicon; an Intel Mac keeps hiding AI (MM-21).
        return .notEligible
        #else
        guard isDeviceEligible, physicalMemory >= model.minimumPhysicalMemory else { return .notEligible }
        // Not downloaded reads as `.unknown` until MM-106 adds its own state;
        // `FallbackAIProvider` never picks this provider in that case anyway.
        guard await isInstalled() else { return AICapabilities(model: .unknown) }
        return AICapabilities(model: .ready, supportedLanguages: model.languages, contextSize: model.contextSize)
        #endif
    }

    public func generateMap(_ request: GenerateMapRequest) async throws -> AIProposal {
        try await respond(.generateMap, .mindMap, language: request.language, locale: request.userLocaleIdentifier,
                          prompt: catalog.prompt(for: request)) { text in
            let answer = try LocalAnswer.decode(LocalAnswer.MindMap.self, from: text)
            let topics = answer.topics.map {
                let parent = $0.parentTemporaryID?.trimmingCharacters(in: .whitespaces) ?? ""
                return ProposedTopic(temporaryID: $0.temporaryID, parentTemporaryID: parent.isEmpty ? nil : parent, title: $0.title)
            }
            let proposal = AIProposal(feature: .generateMap, anchor: .root, suggestedMapTitle: answer.title, topics: topics)
            return try checked(proposal, limit: request.maximumTopics)
        }
    }

    public func expandTopic(_ request: ExpandTopicRequest) async throws -> AIProposal {
        try await topicList(.expandTopic, context: request.context, prompt: catalog.prompt(for: request), limit: request.maximumTopics)
    }

    public func brainstorm(_ request: BrainstormRequest) async throws -> AIProposal {
        try await topicList(.brainstorm, context: request.context, prompt: catalog.prompt(for: request), limit: request.maximumTopics)
    }

    public func findMissingTopics(_ request: MissingTopicsRequest) async throws -> AIProposal {
        try await topicList(.findMissingTopics, context: request.context, prompt: catalog.prompt(for: request), limit: request.maximumTopics)
    }

    public func rewrite(_ request: RewriteRequest) async throws -> AIRewrite {
        let context = request.context
        return try await respond(.rewrite, .rewrites, language: request.outputLanguage,
                                 locale: context.userLocaleIdentifier, prompt: catalog.prompt(for: request)) { text in
            let answer = try LocalAnswer.decode(LocalAnswer.Rewrites.self, from: text)
            var seen: Set<String> = [context.focus.title.lowercased()]
            let suggestions = answer.titles
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
                .prefix(AIProposalLimits.maximumRewriteSuggestions)
            guard !suggestions.isEmpty else { throw AIError.invalidResponse(.empty) }
            return AIRewrite(nodeID: context.focus.nodeID, originalTitle: context.focus.title, suggestions: Array(suggestions))
        }
    }

    public func summarize(_ request: SummarizeRequest) async throws -> AISummary {
        let context = request.context
        return try await respond(.summarize, .summary, language: context.language,
                                 locale: context.userLocaleIdentifier, prompt: catalog.prompt(for: request)) { text in
            let answer = try LocalAnswer.decode(LocalAnswer.Summary.self, from: text)
            let summary = answer.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !summary.isEmpty else { throw AIError.invalidResponse(.empty) }
            return AISummary(nodeID: context.focus.nodeID, text: summary, isPartial: request.isPartial)
        }
    }

    public func suggestTags(_ request: SuggestTagsRequest) async throws -> AITagSuggestions {
        try await respond(.suggestTags, .tags, language: request.language, locale: request.userLocaleIdentifier,
                          prompt: catalog.prompt(for: request)) { text in
            let answer = try LocalAnswer.decode(LocalAnswer.Tags.self, from: text)
            return try Self.invalidIfRejected { try AITagSuggestions.checked(answer.topics.map { ($0.reference, $0.tags) }, for: request) }
        }
    }

    public func suggestGroups(_ request: SuggestGroupsRequest) async throws -> AIGroupSuggestions {
        try await respond(.suggestGroups, .groups, language: request.language, locale: request.userLocaleIdentifier,
                          prompt: catalog.prompt(for: request)) { text in
            let answer = try LocalAnswer.decode(LocalAnswer.Groups.self, from: text)
            return try Self.invalidIfRejected { try AIGroupSuggestions.checked(answer.groups.map { ($0.title, $0.references) }, for: request) }
        }
    }

    public func summarizeBoundary(_ request: SummarizeBoundaryRequest) async throws -> AIBoundaryTitle {
        try await respond(.summarizeBoundary, .title, language: request.language, locale: request.userLocaleIdentifier,
                          prompt: catalog.prompt(for: request)) { text in
            let answer = try LocalAnswer.decode(LocalAnswer.Title.self, from: text)
            return try Self.invalidIfRejected { try AIBoundaryTitle.checked(answer.title, for: request) }
        }
    }

    // MARK: Running a request

    private func topicList(_ feature: AIFeature, context: AIContext, prompt: String, limit: Int) async throws -> AIProposal {
        try await respond(feature, .topicList, language: context.language,
                          locale: context.userLocaleIdentifier, prompt: prompt) { text in
            let answer = try LocalAnswer.decode(LocalAnswer.TopicList.self, from: text)
            let topics = answer.topics.prefix(limit).enumerated().map {
                ProposedTopic(temporaryID: "s\($0.offset + 1)", title: $0.element.title)
            }
            return try checked(AIProposal(feature: feature, anchor: .node(context.focus.nodeID), topics: topics), limit: limit)
        }
    }

    /// Asks the model, then `make` parses and checks the text. An answer `make`
    /// rejects with `invalidResponse` is asked for once more with a reminder
    /// of the shape; other errors (cancellation, the engine failing) end the
    /// request at once.
    private func respond<T>(
        _ feature: AIFeature,
        _ shape: LocalOutputShape,
        language: AILanguage,
        locale: String,
        prompt: String,
        make: (String) throws -> T
    ) async throws -> T {
        let availability = await capabilities().availability(for: feature, in: language)
        guard availability.isReady else { throw AIError.unavailable(availability) }
        let instructions = catalog.instructions(for: feature, language: language, userLocaleIdentifier: locale)
            + "\n" + shape.instruction
        let engine: any LocalInferenceEngine
        do {
            engine = try await self.engine()
        } catch {
            Self.logger.error("Local model failed to load: \(String(describing: type(of: error)), privacy: .public)")
            throw AIError.generationFailed
        }
        var lastError = AIError.invalidResponse(.empty)
        for attempt in 1...Self.maximumAttempts {
            let text = try await generate(with: engine, instructions: instructions, shape: shape,
                                          prompt: attempt == 1 ? prompt : prompt + "\n\n" + Self.retryReminder(for: shape))
            do {
                return try make(text)
            } catch let error as AIError {
                guard case .invalidResponse = error else { throw error }
                // The feature and attempt only: the text is map content.
                Self.logger.notice("Local answer rejected: \(feature.rawValue, privacy: .public) attempt \(attempt, privacy: .public)")
                lastError = error
            }
        }
        throw lastError
    }

    private func generate(with engine: any LocalInferenceEngine, instructions: String, shape: LocalOutputShape, prompt: String) async throws -> String {
        var text = ""
        do {
            // Room for a 30-topic map in Vietnamese, about one token per character.
            for try await piece in engine.generate(instructions: instructions, prompt: prompt, shape: shape, maximumTokens: 1_024) {
                text += piece
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Self.logger.error("Local generation failed: \(String(describing: type(of: error)), privacy: .public)")
            throw AIError.generationFailed
        }
        try Task.checkCancellation()
        return text
    }

    /// Added to the prompt after an answer that could not be used. It names
    /// the shape again rather than quoting the bad answer, which would only
    /// teach the model its own mistake.
    static func retryReminder(for shape: LocalOutputShape) -> String {
        "The previous answer could not be read. " + shape.instruction + "."
    }

    private func checked(_ proposal: AIProposal, limit: Int) throws -> AIProposal {
        try Self.invalidIfRejected {
            _ = try ProposalTranslator.validate(proposal)
            return try ProposalTranslator.limited(proposal, to: limit)
        }
    }

    private static func invalidIfRejected<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let error as ProposalError {
            throw AIError.invalidResponse(error)
        }
    }
}

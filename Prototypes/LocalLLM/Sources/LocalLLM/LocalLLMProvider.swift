import Foundation
import MindMapAIApple
import MindMapAICore
import MindMapDomain

/// The fallback provider: the same prompts as Foundation Models
/// (`PromptCatalog`), sent to a downloaded open model, with the answer checked
/// by `ProposalTranslator` like every other provider's.
///
/// Prototype limits: suggestions arrive as one snapshot (the default
/// `streamSuggestions`), and tags, groups and boundary titles are not built.
public struct LocalLLMProvider: AIProvider {
    public let model: LocalModel
    let store: LocalModelStore
    let engine: @Sendable () async throws -> any LocalInferenceEngine
    let physicalMemory: UInt64
    let catalog = PromptCatalog()

    /// `engine` loads the model on first use, never at launch.
    public init(
        model: LocalModel,
        store: LocalModelStore,
        physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory,
        engine: @escaping @Sendable () async throws -> any LocalInferenceEngine
    ) {
        self.model = model
        self.store = store
        self.physicalMemory = physicalMemory
        self.engine = engine
    }

    public func capabilities() async -> AICapabilities {
        #if arch(x86_64)
        // MLX needs Apple silicon; an Intel Mac keeps hiding AI (MM-21).
        return .notEligible
        #else
        guard physicalMemory >= model.minimumPhysicalMemory else { return .notEligible }
        // No "not downloaded" state exists yet: AIAvailability would need one
        // before this ships [Đề xuất: .modelNotInstalled].
        guard case .installed = await store.state(of: model) else {
            return AICapabilities(model: .unknown)
        }
        return AICapabilities(model: .ready, supportedLanguages: model.languages, contextSize: model.contextSize)
        #endif
    }

    public func generateMap(_ request: GenerateMapRequest) async throws -> AIProposal {
        let answer = try await respond(.generateMap, .mindMap, language: request.language,
                                       locale: request.userLocaleIdentifier, prompt: catalog.prompt(for: request),
                                       as: LocalAnswer.MindMap.self)
        let topics = answer.topics.map {
            let parent = $0.parentTemporaryID?.trimmingCharacters(in: .whitespaces) ?? ""
            return ProposedTopic(temporaryID: $0.temporaryID, parentTemporaryID: parent.isEmpty ? nil : parent, title: $0.title)
        }
        let proposal = AIProposal(feature: .generateMap, anchor: .root, suggestedMapTitle: answer.title, topics: topics)
        return try checked(proposal, limit: request.maximumTopics)
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
        let answer = try await respond(.rewrite, .rewrites, language: request.outputLanguage,
                                       locale: context.userLocaleIdentifier, prompt: catalog.prompt(for: request),
                                       as: LocalAnswer.Rewrites.self)
        var seen: Set<String> = [context.focus.title.lowercased()]
        let suggestions = answer.titles
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .prefix(AIProposalLimits.maximumRewriteSuggestions)
        guard !suggestions.isEmpty else { throw AIError.invalidResponse(.empty) }
        return AIRewrite(nodeID: context.focus.nodeID, originalTitle: context.focus.title, suggestions: Array(suggestions))
    }

    public func summarize(_ request: SummarizeRequest) async throws -> AISummary {
        let context = request.context
        let answer = try await respond(.summarize, .summary, language: context.language,
                                       locale: context.userLocaleIdentifier, prompt: catalog.prompt(for: request),
                                       as: LocalAnswer.Summary.self)
        let text = answer.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AIError.invalidResponse(.empty) }
        return AISummary(nodeID: context.focus.nodeID, text: text, isPartial: request.isPartial)
    }

    public func suggestTags(_ request: SuggestTagsRequest) async throws -> AITagSuggestions {
        throw AIError.generationFailed
    }

    public func suggestGroups(_ request: SuggestGroupsRequest) async throws -> AIGroupSuggestions {
        throw AIError.generationFailed
    }

    public func summarizeBoundary(_ request: SummarizeBoundaryRequest) async throws -> AIBoundaryTitle {
        throw AIError.generationFailed
    }

    // MARK: Running a request

    private func topicList(_ feature: AIFeature, context: AIContext, prompt: String, limit: Int) async throws -> AIProposal {
        let answer = try await respond(feature, .topicList, language: context.language,
                                       locale: context.userLocaleIdentifier, prompt: prompt, as: LocalAnswer.TopicList.self)
        let topics = answer.topics.prefix(limit).enumerated().map {
            ProposedTopic(temporaryID: "s\($0.offset + 1)", title: $0.element.title)
        }
        return try checked(AIProposal(feature: feature, anchor: .node(context.focus.nodeID), topics: topics), limit: limit)
    }

    private func respond<T: Decodable>(
        _ feature: AIFeature,
        _ shape: LocalOutputShape,
        language: AILanguage,
        locale: String,
        prompt: String,
        as type: T.Type
    ) async throws -> T {
        let capabilities = await capabilities()
        let availability = capabilities.availability(for: feature, in: language)
        guard availability.isReady else { throw AIError.unavailable(availability) }
        let instructions = catalog.instructions(for: feature, language: language, userLocaleIdentifier: locale)
            + "\n" + shape.instruction
        let engine = try await engine()
        var text = ""
        // Room for a 30-topic map in Vietnamese, about one token per character.
        for try await piece in engine.generate(instructions: instructions, prompt: prompt, shape: shape, maximumTokens: 1_024) {
            text += piece
        }
        try Task.checkCancellation()
        return try LocalAnswer.decode(type, from: text)
    }

    private func checked(_ proposal: AIProposal, limit: Int) throws -> AIProposal {
        do {
            _ = try ProposalTranslator.validate(proposal)
            return try ProposalTranslator.limited(proposal, to: limit)
        } catch let error as ProposalError {
            throw AIError.invalidResponse(error)
        }
    }
}

import Foundation

/// Caps on how many topics one answer may hold. The Apple provider's
/// `@Guide(.maximumCount)` values must match these, since guides need literals.
/// The numbers are a starting point [Đề xuất], decided for good in MM-8.
public enum AIProposalLimits {
    public static let maximumGeneratedMapTopics = 30
    public static let maximumSuggestedTopics = 12
    public static let maximumRewriteSuggestions = 3

    static func clamp(_ count: Int, to maximum: Int) -> Int {
        min(max(1, count), maximum)
    }
}

/// A new map from one description, such as "Plan a product launch".
public struct GenerateMapRequest: Hashable, Sendable {
    public var prompt: String
    public var language: AILanguage
    public var userLocaleIdentifier: String
    public var maximumTopics: Int

    public init(prompt: String, language: AILanguage, userLocaleIdentifier: String, maximumTopics: Int = 20) {
        self.prompt = prompt
        self.language = language
        self.userLocaleIdentifier = userLocaleIdentifier
        self.maximumTopics = AIProposalLimits.clamp(maximumTopics, to: AIProposalLimits.maximumGeneratedMapTopics)
    }
}

/// Child topics for the focus topic.
public struct ExpandTopicRequest: Hashable, Sendable {
    public var context: AIContext
    public var maximumTopics: Int

    public init(context: AIContext, maximumTopics: Int = 6) {
        self.context = context
        self.maximumTopics = AIProposalLimits.clamp(maximumTopics, to: AIProposalLimits.maximumSuggestedTopics)
    }
}

/// Varied ideas around the focus topic, or around a question the person typed.
public struct BrainstormRequest: Hashable, Sendable {
    public var context: AIContext
    public var question: String?
    public var maximumTopics: Int

    public init(context: AIContext, question: String? = nil, maximumTopics: Int = 8) {
        self.context = context
        self.question = question
        self.maximumTopics = AIProposalLimits.clamp(maximumTopics, to: AIProposalLimits.maximumSuggestedTopics)
    }
}

public enum RewriteStyle: String, Hashable, Sendable, CaseIterable, Codable {
    case shorter
    case clearer
    case formal
    case simpler
    case technical
    case vietnamese
    case english

    /// Translating styles decide the output language themselves.
    public var outputLanguage: AILanguage? {
        switch self {
        case .vietnamese: .vietnamese
        case .english: .english
        case .shorter, .clearer, .formal, .simpler, .technical: nil
        }
    }
}

/// Alternative titles for the focus topic.
public struct RewriteRequest: Hashable, Sendable {
    public var context: AIContext
    public var style: RewriteStyle

    public init(context: AIContext, style: RewriteStyle) {
        self.context = context
        self.style = style
    }

    /// The style's language for a translation, else the context's language.
    public var outputLanguage: AILanguage {
        style.outputLanguage ?? context.language
    }
}

/// A summary of the branch in the context.
///
/// For a branch too large for one request, summarize each of
/// `AIContextBuilder.chunkContexts` first, then send their texts here as
/// `partialSummaries` to combine them.
public struct SummarizeRequest: Hashable, Sendable {
    public var context: AIContext
    public var partialSummaries: [String]

    public init(context: AIContext, partialSummaries: [String] = []) {
        self.context = context
        self.partialSummaries = partialSummaries
    }

    /// True when the answer covers part of the branch only. Partial summaries
    /// already cover what the context left out, so combining them is whole.
    public var isPartial: Bool {
        context.isTruncated && partialSummaries.isEmpty
    }
}

/// Topics the branch may be missing, offered as suggestions, not corrections.
public struct MissingTopicsRequest: Hashable, Sendable {
    public var context: AIContext
    public var maximumTopics: Int

    public init(context: AIContext, maximumTopics: Int = 5) {
        self.context = context
        self.maximumTopics = AIProposalLimits.clamp(maximumTopics, to: AIProposalLimits.maximumSuggestedTopics)
    }
}

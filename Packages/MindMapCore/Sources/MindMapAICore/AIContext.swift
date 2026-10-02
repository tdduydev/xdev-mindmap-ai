import Foundation
import MindMapDomain

/// One topic as the model sees it: text only, already shortened.
public struct ContextTopic: Hashable, Sendable {
    public let nodeID: NodeID
    public let parentID: NodeID?
    public let title: String
    public let note: String?
    /// Levels below the focus topic: 0 for the focus and its siblings, 1 for its
    /// children, -1 for its parent.
    public let depth: Int

    public init(nodeID: NodeID, parentID: NodeID?, title: String, note: String? = nil, depth: Int) {
        self.nodeID = nodeID
        self.parentID = parentID
        self.title = title
        self.note = note
        self.depth = depth
    }
}

/// The part of a map sent with one AI request. Built by `AIContextBuilder`,
/// bounded in size, and never the whole map.
public struct AIContext: Hashable, Sendable {
    public let mapID: MapID
    public let mapTitle: String
    public let focus: ContextTopic
    /// Root first, parent last. Long chains keep the root and the nearest levels.
    public let ancestors: [ContextTopic]
    public let siblings: [ContextTopic]
    /// Pre-order, so it reads as an outline under the focus.
    public let descendants: [ContextTopic]
    /// Topics joined to the focus by a cross-link.
    public let linkedTopics: [ContextTopic]
    /// Descendants of the focus that did not fit. Above zero, a summary covers
    /// only part of the branch; `AIContextBuilder.chunkContexts` covers it all.
    public let omittedDescendantCount: Int
    /// The language the model must answer in.
    public let language: AILanguage
    /// The person's locale, named in the instructions as Apple recommends.
    public let userLocaleIdentifier: String
    /// What the topic text costs, by `TokenEstimator`. Instructions and output
    /// come on top.
    public let estimatedTokens: Int

    public init(
        mapID: MapID,
        mapTitle: String,
        focus: ContextTopic,
        ancestors: [ContextTopic] = [],
        siblings: [ContextTopic] = [],
        descendants: [ContextTopic] = [],
        linkedTopics: [ContextTopic] = [],
        omittedDescendantCount: Int = 0,
        language: AILanguage,
        userLocaleIdentifier: String,
        estimatedTokens: Int = 0
    ) {
        self.mapID = mapID
        self.mapTitle = mapTitle
        self.focus = focus
        self.ancestors = ancestors
        self.siblings = siblings
        self.descendants = descendants
        self.linkedTopics = linkedTopics
        self.omittedDescendantCount = omittedDescendantCount
        self.language = language
        self.userLocaleIdentifier = userLocaleIdentifier
        self.estimatedTokens = estimatedTokens
    }

    public var isTruncated: Bool { omittedDescendantCount > 0 }
}

/// How much of a map one request may carry.
///
/// The default numbers are a starting point [Đề xuất], to be tuned against the
/// real model in MM-8.
public struct AIContextLimits: Hashable, Sendable {
    /// What the on-device model offered on the development Mac (docs/on-device-ai.md).
    public static let assumedContextSize = 4_096

    public var maximumDepth: Int
    public var maximumDescendants: Int
    public var maximumAncestors: Int
    public var maximumSiblings: Int
    public var maximumLinkedTopics: Int
    public var maximumTitleLength: Int
    public var maximumNoteLength: Int
    /// Tokens the topic text may use.
    public var tokenBudget: Int

    public init(
        contextSize: Int? = nil,
        maximumDepth: Int = 3,
        maximumDescendants: Int = 60,
        maximumAncestors: Int = 6,
        maximumSiblings: Int = 12,
        maximumLinkedTopics: Int = 8,
        maximumTitleLength: Int = 120,
        maximumNoteLength: Int = 300
    ) {
        self.maximumDepth = maximumDepth
        self.maximumDescendants = maximumDescendants
        self.maximumAncestors = max(1, maximumAncestors)
        self.maximumSiblings = maximumSiblings
        self.maximumLinkedTopics = maximumLinkedTopics
        self.maximumTitleLength = maximumTitleLength
        self.maximumNoteLength = maximumNoteLength
        // The context window holds instructions, the output schema, this text
        // and the answer. Giving the map text 40% leaves room for a dozen
        // Vietnamese topics in the answer, at about one token per character.
        let size = contextSize ?? Self.assumedContextSize
        self.tokenBudget = max(256, size * 2 / 5)
    }
}

/// A rough, deliberately high token count for text that has no model at hand.
///
/// [Inference] English runs about four characters per token; Vietnamese runs
/// about one token per character (docs/on-device-ai.md). Any non-ASCII character
/// marks the text as Vietnamese, so mixed text is counted the expensive way.
public enum TokenEstimator {
    public static func estimate(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        if text.unicodeScalars.contains(where: { !$0.isASCII }) {
            return text.count
        }
        return (text.utf8.count + 2) / 3
    }

    /// One outline line: the text plus the bullet, indentation and line break.
    static func estimateLine(_ text: String) -> Int {
        estimate(text) + 3
    }
}

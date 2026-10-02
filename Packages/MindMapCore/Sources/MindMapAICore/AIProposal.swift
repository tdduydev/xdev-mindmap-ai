import Foundation
import MindMapDomain

/// Where the top level of a proposal attaches.
public enum ProposalAnchor: Hashable, Sendable {
    /// Under the map's central topic: a generated map, applied to a new map.
    case root
    /// Under an existing topic.
    case node(NodeID)
}

/// A topic the model suggests. It has a temporary ID only, and becomes a real
/// node only when the person accepts it.
public struct ProposedTopic: Hashable, Sendable, Identifiable {
    public var temporaryID: String
    /// Nil, or empty, for a topic directly under the anchor.
    public var parentTemporaryID: String?
    public var title: String
    public var note: String?

    public init(temporaryID: String, parentTemporaryID: String? = nil, title: String, note: String? = nil) {
        self.temporaryID = temporaryID
        self.parentTemporaryID = parentTemporaryID
        self.title = title
        self.note = note
    }

    public var id: String { temporaryID }
}

/// Suggested topics from one AI request. Never persisted: the preview edits it,
/// and `ProposalTranslator` turns the accepted part into one command.
public struct AIProposal: Hashable, Sendable {
    public var feature: AIFeature
    public var anchor: ProposalAnchor
    /// The title the model gave a generated map.
    public var suggestedMapTitle: String?
    public var topics: [ProposedTopic]

    public init(feature: AIFeature, anchor: ProposalAnchor, suggestedMapTitle: String? = nil, topics: [ProposedTopic]) {
        self.feature = feature
        self.anchor = anchor
        self.suggestedMapTitle = suggestedMapTitle
        self.topics = topics
    }
}

/// Alternative titles for one topic.
public struct AIRewrite: Hashable, Sendable {
    public var nodeID: NodeID
    public var originalTitle: String
    public var suggestions: [String]

    public init(nodeID: NodeID, originalTitle: String, suggestions: [String]) {
        self.nodeID = nodeID
        self.originalTitle = originalTitle
        self.suggestions = suggestions
    }
}

/// A summary of a branch. It goes into the topic's note only if the person
/// chooses to keep it.
public struct AISummary: Hashable, Sendable {
    public var nodeID: NodeID
    public var text: String
    /// True when the summary was written from part of the branch only.
    public var isPartial: Bool

    public init(nodeID: NodeID, text: String, isPartial: Bool = false) {
        self.nodeID = nodeID
        self.text = text
        self.isPartial = isPartial
    }
}

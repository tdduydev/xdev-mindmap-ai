import Foundation
import MindMapDomain

/// A live map, as `list_maps` and the chat's `listMaps` show it.
public struct MapListing: Hashable, Sendable {
    public let mapID: MapID
    public let title: String
    public let topicCount: Int
    public let updatedAt: Date
}

/// A topic named by ID and title, for paths, children and links.
public struct TopicSummary: Hashable, Sendable {
    public let nodeID: NodeID
    public let title: String
}

/// One row of an outline. `depth` is 0 for the topic the outline starts at.
public struct OutlineTopic: Hashable, Sendable {
    public let nodeID: NodeID
    public let depth: Int
    public let title: String
    /// Nil when notes were not asked for or the topic has none.
    public let note: String?
    /// True when the note was cut to fit the limit.
    public let isNoteCut: Bool
    /// Children in the map, whether or not the outline shows them.
    public let childCount: Int
    /// Heads a floating branch: no parent, listed after the main tree.
    public let isFloating: Bool
}

/// A map or a branch, top to bottom, cut to a `TextLimit`. Collapsed branches
/// are included: a reader asks about the map, not about the window.
public struct OutlineExcerpt: Hashable, Sendable {
    public let mapID: MapID
    public let mapTitle: String
    /// A prefix of the branch in reading order, so the rows always form a tree.
    public let topics: [OutlineTopic]
    /// Topics within the asked depth that did not fit the limit, for "N more topics".
    public let omittedTopicCount: Int
    /// Topics below the asked depth.
    public let deeperTopicCount: Int
}

/// A topic that matches a search.
public struct TopicHit: Hashable, Sendable {
    public enum Match: Hashable, Sendable {
        case title
        case note
    }

    public let ref: TopicRef
    public let mapTitle: String
    public let title: String
    /// Titles from the central topic down to the parent; empty for the central topic.
    public let path: [String]
    public let match: Match
    /// The note line that holds most of the words, shortened; nil for a title match.
    public let excerpt: String?
}

/// Everything about one topic that a reader can ask for.
public struct TopicDetail: Hashable, Sendable {
    /// Another topic this one is cross-linked with (`MindEdge`, not hierarchy).
    public struct CrossLink: Hashable, Sendable {
        public enum Direction: Hashable, Sendable {
            case outgoing
            case incoming
        }

        public let topic: TopicSummary
        public let label: String?
        public let direction: Direction
    }

    public let ref: TopicRef
    public let mapTitle: String
    public let title: String
    public let note: String?
    /// From the central topic down to the parent.
    public let path: [TopicSummary]
    public let children: [TopicSummary]
    /// Tag names, in the order the topic lists them.
    public let tags: [String]
    public let taskState: TaskState?
    public let priority: TaskPriority?
    public let startDate: CalendarDay?
    public let dueDate: CalendarDay?
    public let crossLinks: [CrossLink]
}

public enum MapQueryError: Error, Hashable, Sendable {
    /// No live map has this ID: it never existed, was deleted, or is in Recently Deleted.
    case mapNotFound
    case topicNotFound
}

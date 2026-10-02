import Foundation

/// A frame (boundary) or a bracket (summary) around a run of adjacent
/// siblings and their branches.
///
/// Members are positional: every child of `parentNodeID` from `firstNodeID` to
/// `lastNodeID` in display order. A topic added inside the run joins it and a
/// topic moved out leaves it, so the group never holds a stale member list.
/// It is not a second parent: hierarchy stays `MindNode.parentID` (ADR 0004).
public struct MindGroup: Identifiable, Hashable, Sendable, Codable {
    public let id: GroupID
    public let mapID: MapID
    public var kind: GroupKind
    public var parentNodeID: NodeID?
    public var firstNodeID: NodeID?
    public var lastNodeID: NodeID?
    public var title: String?
    public var color: TopicColor?
    public var origin: NodeOrigin
    /// For a summary: the summary topic, a child of `parentNodeID` that is
    /// left out of every sibling run. Ignored for other kinds.
    public var summaryNodeID: NodeID?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: GroupID = GroupID(),
        mapID: MapID,
        kind: GroupKind = .boundary,
        parentNodeID: NodeID?,
        firstNodeID: NodeID?,
        lastNodeID: NodeID?,
        title: String? = nil,
        color: TopicColor? = nil,
        origin: NodeOrigin = .user,
        createdAt: Date = .now,
        updatedAt: Date? = nil,
        summaryNodeID: NodeID? = nil
    ) {
        self.id = id
        self.mapID = mapID
        self.kind = kind
        self.parentNodeID = parentNodeID
        self.firstNodeID = firstNodeID
        self.lastNodeID = lastNodeID
        self.title = title
        self.color = color
        self.origin = origin
        self.summaryNodeID = summaryNodeID
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

/// `boundary` and `summary` are built; `zone` is reserved. A kind this build
/// does not know is hidden and kept as it is.
public struct GroupKind: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let boundary = GroupKind(rawValue: "boundary")
    public static let summary = GroupKind(rawValue: "summary")

    /// Kinds whose members this build computes and keeps valid.
    public var isRun: Bool { self == .boundary || self == .summary }
}

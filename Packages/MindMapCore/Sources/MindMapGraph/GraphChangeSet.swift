import Foundation
import MindMapDomain

/// One value before and after a change. `before == nil` means it was created;
/// `after == nil` means it was deleted.
public struct EntityChange<Value: Hashable & Sendable>: Hashable, Sendable {
    public let before: Value?
    public let after: Value?

    public init(before: Value?, after: Value?) {
        self.before = before
        self.after = after
    }

    public var reversed: EntityChange {
        EntityChange(before: after, after: before)
    }
}

/// Exactly what one command changed, with the old and new value of every
/// touched node, edge, tag, tag link, group and map.
///
/// It serves two jobs: persistence writes only these records, and undo applies
/// the reversed set. Because undo replays recorded values instead of a
/// hand-written inverse per command, side effects such as renumbering siblings
/// are undone exactly.
public struct GraphChangeSet: Hashable, Sendable {
    public private(set) var nodes: [NodeID: EntityChange<MindNode>] = [:]
    public private(set) var edges: [EdgeID: EntityChange<MindEdge>] = [:]
    public private(set) var tags: [TagID: EntityChange<MindTag>] = [:]
    public private(set) var nodeTags: [NodeTagID: EntityChange<MindNodeTag>] = [:]
    public private(set) var groups: [GroupID: EntityChange<MindGroup>] = [:]
    public private(set) var map: EntityChange<MindMap>?

    public init() {}

    public var isEmpty: Bool {
        nodes.isEmpty && edges.isEmpty && tags.isEmpty && nodeTags.isEmpty && groups.isEmpty && map == nil
    }

    public func reversed() -> GraphChangeSet {
        var result = GraphChangeSet()
        result.nodes = nodes.mapValues(\.reversed)
        result.edges = edges.mapValues(\.reversed)
        result.tags = tags.mapValues(\.reversed)
        result.nodeTags = nodeTags.mapValues(\.reversed)
        result.groups = groups.mapValues(\.reversed)
        result.map = map?.reversed
        return result
    }

    // MARK: Persistence views

    public var savedNodes: [MindNode] { nodes.values.compactMap(\.after) }
    public var deletedNodeIDs: [NodeID] { nodes.filter { $0.value.after == nil }.map(\.key) }
    public var savedEdges: [MindEdge] { edges.values.compactMap(\.after) }
    public var deletedEdgeIDs: [EdgeID] { edges.filter { $0.value.after == nil }.map(\.key) }
    public var savedTags: [MindTag] { tags.values.compactMap(\.after) }
    public var deletedTagIDs: [TagID] { tags.filter { $0.value.after == nil }.map(\.key) }
    public var savedNodeTags: [MindNodeTag] { nodeTags.values.compactMap(\.after) }
    public var deletedNodeTagIDs: [NodeTagID] { nodeTags.filter { $0.value.after == nil }.map(\.key) }
    public var savedGroups: [MindGroup] { groups.values.compactMap(\.after) }
    public var deletedGroupIDs: [GroupID] { groups.filter { $0.value.after == nil }.map(\.key) }

    // MARK: Recording

    mutating func recordNode(_ id: NodeID, before: MindNode?, after: MindNode?) {
        nodes[id] = Self.merged(nodes[id], before: before, after: after)
    }

    mutating func recordEdge(_ id: EdgeID, before: MindEdge?, after: MindEdge?) {
        edges[id] = Self.merged(edges[id], before: before, after: after)
    }

    mutating func recordTag(_ id: TagID, before: MindTag?, after: MindTag?) {
        tags[id] = Self.merged(tags[id], before: before, after: after)
    }

    mutating func recordNodeTag(_ id: NodeTagID, before: MindNodeTag?, after: MindNodeTag?) {
        nodeTags[id] = Self.merged(nodeTags[id], before: before, after: after)
    }

    mutating func recordGroup(_ id: GroupID, before: MindGroup?, after: MindGroup?) {
        groups[id] = Self.merged(groups[id], before: before, after: after)
    }

    mutating func recordMap(before: MindMap, after: MindMap) {
        map = Self.merged(map, before: before, after: after)
    }

    /// Several steps on one value collapse into one change from its first
    /// `before` to its last `after`; a change that ends where it started is dropped.
    private static func merged<Value>(
        _ existing: EntityChange<Value>?,
        before: Value?,
        after: Value?
    ) -> EntityChange<Value>? {
        let originalBefore = existing.map(\.before) ?? before
        guard originalBefore != after else { return nil }
        return EntityChange(before: originalBefore, after: after)
    }
}

import Foundation
import MindMapDomain

/// The in-memory graph of one map: a pure value, independent of SwiftUI,
/// persistence and screen coordinates.
///
/// Outside this module the state is read-only. Changes go through a
/// `GraphCommand` executed by `GraphEngine`, which validates the result and
/// records it for undo.
public struct GraphState: Sendable {
    public private(set) var map: MindMap
    public private(set) var nodes: [NodeID: MindNode]
    public private(set) var edges: [EdgeID: MindEdge]
    /// The map's own tags and the shared (library) tags loaded with it.
    public private(set) var tags: [TagID: MindTag]
    public private(set) var nodeTags: [NodeTagID: MindNodeTag]
    public private(set) var groups: [GroupID: MindGroup]
    /// Without bytes (`MindImage.data` is always nil here); the repository's
    /// `imageData(for:)` reads them when they are drawn.
    public private(set) var images: [ImageID: MindImage]

    /// Children of each parent in display order. Derived from `nodes` and kept
    /// in step by the mutation primitives, so reading children never sorts.
    private var childIndex: [NodeID: [NodeID]]

    /// An empty map with no root yet.
    public init(map: MindMap) {
        self.init(map: map, nodes: [], edges: [])
    }

    /// Builds a state from stored values without checking invariants. Data that
    /// arrived through sync can be inconsistent, so run `GraphRepair` before editing.
    ///
    /// Tags of other maps are dropped; shared tags (`mapID` nil) are kept.
    public init(
        map: MindMap,
        nodes: some Sequence<MindNode>,
        edges: some Sequence<MindEdge>,
        tags: [MindTag] = [],
        nodeTags: [MindNodeTag] = [],
        groups: [MindGroup] = [],
        images: [MindImage] = []
    ) {
        self.map = map
        var nodeTable: [NodeID: MindNode] = [:]
        for node in nodes where node.mapID == map.id {
            // Sync can deliver the same node twice; the newest copy wins.
            if let existing = nodeTable[node.id], existing.updatedAt > node.updatedAt { continue }
            nodeTable[node.id] = node
        }
        var edgeTable: [EdgeID: MindEdge] = [:]
        for edge in edges where edge.mapID == map.id {
            if let existing = edgeTable[edge.id], existing.updatedAt > edge.updatedAt { continue }
            edgeTable[edge.id] = edge
        }
        self.nodes = nodeTable
        self.edges = edgeTable
        self.tags = Self.newestByID(tags.filter { $0.mapID == nil || $0.mapID == map.id })
        self.nodeTags = Self.newestByID(nodeTags.filter { $0.mapID == map.id })
        self.groups = Self.newestByID(groups.filter { $0.mapID == map.id })
        self.images = Self.newestByID(images.filter { $0.mapID == map.id }.map(\.withoutData))
        self.childIndex = Self.makeChildIndex(for: nodeTable)
    }

    /// Sync can deliver the same record twice; the newest copy wins.
    private static func newestByID<Value: Identifiable>(_ values: [Value]) -> [Value.ID: Value]
    where Value: StoredValue {
        var table: [Value.ID: Value] = [:]
        for value in values {
            if let existing = table[value.id], existing.updatedAt > value.updatedAt { continue }
            table[value.id] = value
        }
        return table
    }

    // MARK: Reading

    public var root: MindNode? {
        map.rootNodeID.flatMap { nodes[$0] }
    }

    public var isEmpty: Bool { nodes.isEmpty }

    public func node(_ id: NodeID) -> MindNode? {
        nodes[id]
    }

    public func childIDs(of id: NodeID) -> [NodeID] {
        childIndex[id] ?? []
    }

    public func children(of id: NodeID) -> [MindNode] {
        childIDs(of: id).compactMap { nodes[$0] }
    }

    public func edges(touching id: NodeID) -> [MindEdge] {
        edges.values.filter { $0.sourceNodeID == id || $0.targetNodeID == id }
    }

    // MARK: Reading organization

    public func tag(_ id: TagID) -> MindTag? {
        tags[id]
    }

    public func group(_ id: GroupID) -> MindGroup? {
        groups[id]
    }

    /// The topic's tag links whose tag is loaded, oldest first. A link whose
    /// tag has not synced yet is kept in storage but not shown.
    public func nodeTags(of nodeID: NodeID) -> [MindNodeTag] {
        // Links made in one step share a timestamp; the tag's own place in the
        // map's tag list breaks the tie before the random ID does, so chips keep
        // one order on every device and every run.
        let rank = { (link: MindNodeTag) in self.tags[link.tagID]?.sortOrder ?? 0 }
        return nodeTags.values
            .filter { $0.nodeID == nodeID && tags[$0.tagID] != nil }
            .sorted { ($0.createdAt, rank($0), $0.id) < ($1.createdAt, rank($1), $1.id) }
    }

    public func tags(of nodeID: NodeID) -> [MindTag] {
        nodeTags(of: nodeID).compactMap { tags[$0.tagID] }
    }

    /// The tag a typed name refers to: a shared tag first, then a map tag, as
    /// the tag field offers them. Nil when no tag has the name's key.
    public func tag(named name: String) -> MindTag? {
        guard let normalized = MindTag.normalizedName(name) else { return nil }
        let key = MindTag.key(for: normalized)
        let matches = tags.values
            .filter { $0.key == key }
            .sorted { ($0.isShared ? 0 : 1, $0.createdAt, $0.id) < ($1.isShared ? 0 : 1, $1.createdAt, $1.id) }
        return matches.first
    }

    /// The siblings a group covers, in display order. Nil when the group is not
    /// a boundary or summary or its endpoints are not a run of siblings.
    public func members(of group: MindGroup) -> [NodeID]? {
        guard group.kind.isRun,
              let parentID = group.parentNodeID, nodes[parentID] != nil,
              let firstID = group.firstNodeID, let lastID = group.lastNodeID
        else { return nil }
        let siblings = runSiblingIDs(of: parentID)
        guard let first = siblings.firstIndex(of: firstID), let last = siblings.firstIndex(of: lastID), first <= last
        else { return nil }
        return Array(siblings[first...last])
    }

    /// Children of `parentID` that a boundary or summary may span, in display
    /// order: every child except the summary topics under it.
    public func runSiblingIDs(of parentID: NodeID) -> [NodeID] {
        let children = childIDs(of: parentID)
        let excluded = summaryTopicIDs(under: parentID)
        return excluded.isEmpty ? children : children.filter { !excluded.contains($0) }
    }

    /// Children of `parentID` that a summary group under it names. Being named
    /// is what makes a topic a summary topic; nothing on the node says so.
    public func summaryTopicIDs(under parentID: NodeID) -> Set<NodeID> {
        var ids: Set<NodeID> = []
        for group in groups.values where group.kind == .summary && group.parentNodeID == parentID {
            if let id = group.summaryNodeID, nodes[id]?.parentID == parentID { ids.insert(id) }
        }
        return ids
    }

    /// The summary groups naming a topic, oldest first.
    public func summaries(naming nodeID: NodeID) -> [MindGroup] {
        groups.values
            .filter { $0.kind == .summary && $0.summaryNodeID == nodeID }
            .sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    /// The topic's image, the newest if sync left two.
    public func image(of nodeID: NodeID) -> MindImage? {
        images(of: nodeID).last
    }

    /// Oldest first.
    func images(of nodeID: NodeID) -> [MindImage] {
        images.values
            .filter { $0.nodeID == nodeID }
            .sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    /// Topics with no parent that are not the central topic and have a position.
    public var floatingTopicIDs: [NodeID] {
        nodes.values
            .filter { $0.isFloating(rootID: map.rootNodeID) }
            .sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
            .map(\.id)
    }

    /// Boundaries and summaries over children of `parentID`.
    public func groups(under parentID: NodeID) -> [MindGroup] {
        groups.values
            .filter { $0.parentNodeID == parentID }
            .sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    // MARK: Mutation primitives
    //
    // These keep `childIndex` consistent and nothing else. They do not check
    // invariants or record changes; `GraphTransaction` does both.

    mutating func insertNode(_ node: MindNode) {
        nodes[node.id] = node
        if let parentID = node.parentID {
            insertIntoChildIndex(node.id, parentID: parentID)
        }
    }

    mutating func replaceNode(_ node: MindNode) {
        guard let old = nodes[node.id] else {
            insertNode(node)
            return
        }
        let positionChanged = old.parentID != node.parentID || old.siblingOrderKey != node.siblingOrderKey
        if positionChanged, let oldParentID = old.parentID {
            removeFromChildIndex(node.id, parentID: oldParentID)
        }
        nodes[node.id] = node
        if positionChanged, let parentID = node.parentID {
            insertIntoChildIndex(node.id, parentID: parentID)
        }
    }

    @discardableResult
    mutating func removeNode(_ id: NodeID) -> MindNode? {
        guard let node = nodes.removeValue(forKey: id) else { return nil }
        if let parentID = node.parentID {
            removeFromChildIndex(id, parentID: parentID)
        }
        return node
    }

    mutating func upsertEdge(_ edge: MindEdge) {
        edges[edge.id] = edge
    }

    @discardableResult
    mutating func removeEdge(_ id: EdgeID) -> MindEdge? {
        edges.removeValue(forKey: id)
    }

    mutating func upsertTag(_ tag: MindTag) {
        tags[tag.id] = tag
    }

    @discardableResult
    mutating func removeTag(_ id: TagID) -> MindTag? {
        tags.removeValue(forKey: id)
    }

    mutating func upsertNodeTag(_ link: MindNodeTag) {
        nodeTags[link.id] = link
    }

    @discardableResult
    mutating func removeNodeTag(_ id: NodeTagID) -> MindNodeTag? {
        nodeTags.removeValue(forKey: id)
    }

    mutating func upsertGroup(_ group: MindGroup) {
        groups[group.id] = group
    }

    @discardableResult
    mutating func removeGroup(_ id: GroupID) -> MindGroup? {
        groups.removeValue(forKey: id)
    }

    mutating func upsertImage(_ image: MindImage) {
        images[image.id] = image.withoutData
    }

    @discardableResult
    mutating func removeImage(_ id: ImageID) -> MindImage? {
        images.removeValue(forKey: id)
    }

    mutating func setMap(_ newMap: MindMap) {
        precondition(newMap.id == map.id, "A graph cannot switch to another map")
        map = newMap
    }

    /// Marks the map as edited. Not part of undo history: undoing is an edit too.
    mutating func touch(at date: Date) {
        map.updatedAt = date
    }

    /// Applies a recorded change set exactly, in either direction.
    mutating func apply(_ changes: GraphChangeSet) {
        for (id, change) in changes.nodes {
            if let after = change.after {
                replaceNode(after)
            } else {
                removeNode(id)
            }
        }
        for (id, change) in changes.edges {
            if let after = change.after {
                upsertEdge(after)
            } else {
                removeEdge(id)
            }
        }
        apply(changes.tags, upsert: { $0.upsertTag($1) }, remove: { $0.removeTag($1) })
        apply(changes.nodeTags, upsert: { $0.upsertNodeTag($1) }, remove: { $0.removeNodeTag($1) })
        apply(changes.groups, upsert: { $0.upsertGroup($1) }, remove: { $0.removeGroup($1) })
        apply(changes.images, upsert: { $0.upsertImage($1) }, remove: { $0.removeImage($1) })
        if let map = changes.map?.after {
            setMap(map)
        }
    }

    private mutating func apply<ID, Value>(
        _ changes: [ID: EntityChange<Value>],
        upsert: (inout GraphState, Value) -> Void,
        remove: (inout GraphState, ID) -> Void
    ) {
        for (id, change) in changes {
            if let after = change.after {
                upsert(&self, after)
            } else {
                remove(&self, id)
            }
        }
    }

    // MARK: Child index

    private mutating func insertIntoChildIndex(_ id: NodeID, parentID: NodeID) {
        guard let key = nodes[id]?.siblingOrderKey else { return }
        var siblings = childIndex[parentID] ?? []
        let index = insertionIndex(for: key, in: siblings)
        siblings.insert(id, at: index)
        childIndex[parentID] = siblings
    }

    private mutating func removeFromChildIndex(_ id: NodeID, parentID: NodeID) {
        guard var siblings = childIndex[parentID], let index = siblings.firstIndex(of: id) else { return }
        siblings.remove(at: index)
        childIndex[parentID] = siblings.isEmpty ? nil : siblings
    }

    /// Binary search over siblings that are already in display order.
    private func insertionIndex(for key: SiblingOrderKey, in siblings: [NodeID]) -> Int {
        var low = 0
        var high = siblings.count
        while low < high {
            let mid = (low + high) / 2
            if let midKey = nodes[siblings[mid]]?.siblingOrderKey, midKey < key {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    private static func makeChildIndex(for nodes: [NodeID: MindNode]) -> [NodeID: [NodeID]] {
        var grouped: [NodeID: [MindNode]] = [:]
        for node in nodes.values {
            guard let parentID = node.parentID else { continue }
            grouped[parentID, default: []].append(node)
        }
        return grouped.mapValues { siblings in
            siblings.sorted { $0.siblingOrderKey < $1.siblingOrderKey }.map(\.id)
        }
    }
}

extension GraphState: Equatable {
    /// Equal when the stored content is equal; the child index is derived.
    public static func == (lhs: GraphState, rhs: GraphState) -> Bool {
        lhs.map == rhs.map && lhs.nodes == rhs.nodes && lhs.edges == rhs.edges
            && lhs.tags == rhs.tags && lhs.nodeTags == rhs.nodeTags && lhs.groups == rhs.groups
            && lhs.images == rhs.images
    }
}

/// Display order among siblings. Two devices can give siblings the same
/// `sortOrder`, so creation time and then ID break ties the same way everywhere.
struct SiblingOrderKey: Comparable {
    let sortOrder: Double
    let createdAt: Date
    let id: NodeID

    static func < (lhs: SiblingOrderKey, rhs: SiblingOrderKey) -> Bool {
        (lhs.sortOrder, lhs.createdAt, lhs.id) < (rhs.sortOrder, rhs.createdAt, rhs.id)
    }
}

/// A stored value that sync can deliver more than once.
protocol StoredValue {
    var updatedAt: Date { get }
}

extension MindTag: StoredValue {}
extension MindNodeTag: StoredValue {}
extension MindGroup: StoredValue {}
extension MindImage: StoredValue {}

extension MindNode {
    var siblingOrderKey: SiblingOrderKey {
        SiblingOrderKey(sortOrder: sortOrder, createdAt: createdAt, id: id)
    }
}

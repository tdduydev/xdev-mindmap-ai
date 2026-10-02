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

    /// Children of each parent in display order. Derived from `nodes` and kept
    /// in step by the mutation primitives, so reading children never sorts.
    private var childIndex: [NodeID: [NodeID]]

    /// An empty map with no root yet.
    public init(map: MindMap) {
        self.init(map: map, nodes: [], edges: [])
    }

    /// Builds a state from stored values without checking invariants. Data that
    /// arrived through sync can be inconsistent, so run `GraphRepair` before editing.
    public init(map: MindMap, nodes: some Sequence<MindNode>, edges: some Sequence<MindEdge>) {
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
        self.childIndex = Self.makeChildIndex(for: nodeTable)
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
        if let map = changes.map?.after {
            setMap(map)
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

extension MindNode {
    var siblingOrderKey: SiblingOrderKey {
        SiblingOrderKey(sortOrder: sortOrder, createdAt: createdAt, id: id)
    }
}

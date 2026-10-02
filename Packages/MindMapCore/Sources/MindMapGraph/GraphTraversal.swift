import Foundation
import MindMapDomain

/// One row of the map read top to bottom.
public struct OutlineItem: Hashable, Sendable {
    public let nodeID: NodeID
    public let depth: Int
    public let hasChildren: Bool
}

// Walks are iterative and track visited nodes, so a deep map cannot overflow
// the stack and a corrupt parent loop cannot hang the app.
extension GraphState {
    /// Parent first, root last. Empty for the root or an unknown node.
    public func ancestors(of id: NodeID) -> [NodeID] {
        var result: [NodeID] = []
        var visited: Set<NodeID> = [id]
        var current = nodes[id]?.parentID
        while let parentID = current, nodes[parentID] != nil, visited.insert(parentID).inserted {
            result.append(parentID)
            current = nodes[parentID]?.parentID
        }
        return result
    }

    /// Every node below `id`, depth-first in display order, without `id` itself.
    public func descendants(of id: NodeID) -> [NodeID] {
        var result: [NodeID] = []
        var visited: Set<NodeID> = [id]
        var stack = Array(childIDs(of: id).reversed())
        while let next = stack.popLast() {
            guard visited.insert(next).inserted else { continue }
            result.append(next)
            stack.append(contentsOf: childIDs(of: next).reversed())
        }
        return result
    }

    /// Nodes with the same parent, in display order, without `id` itself.
    public func siblings(of id: NodeID) -> [NodeID] {
        guard let parentID = nodes[id]?.parentID else { return [] }
        return childIDs(of: parentID).filter { $0 != id }
    }

    /// 0 for the root. Nil when the node is not connected to the root.
    public func depth(of id: NodeID) -> Int? {
        guard nodes[id] != nil, let rootID = map.rootNodeID else { return nil }
        if id == rootID { return 0 }
        let chain = ancestors(of: id)
        return chain.last == rootID ? chain.count : nil
    }

    public func isAncestor(_ ancestorID: NodeID, of id: NodeID) -> Bool {
        ancestors(of: id).contains(ancestorID)
    }

    /// The tops of the map's trees: the central topic, then each floating
    /// topic in layout order. Empty when the map has no central topic.
    public var topLevelIDs: [NodeID] {
        guard let rootID = map.rootNodeID, nodes[rootID] != nil else { return [] }
        return [rootID] + floatingTopicIDs
    }

    /// Every topic a reader can reach, pre-order with every branch open: the
    /// main tree, then each floating branch (FR-ORG-27). Depth is the level a
    /// topic is drawn at, as in `visibleOutline()`.
    public func readingOrder() -> [(id: NodeID, depth: Int)] {
        var result: [(id: NodeID, depth: Int)] = []
        var visited: Set<NodeID> = []
        var stack = topLevelStack()
        while let (id, depth) = stack.popLast() {
            guard nodes[id] != nil, visited.insert(id).inserted else { continue }
            result.append((id, depth))
            stack.append(contentsOf: childIDs(of: id).reversed().map { ($0, depth + 1) })
        }
        return result
    }

    /// A floating topic is drawn as a main topic (level 1, its own branch
    /// colour), so it starts one level below the central topic although it
    /// has no parent.
    private func topLevelStack() -> [(id: NodeID, depth: Int)] {
        topLevelIDs.enumerated().reversed().map { ($0.element, $0.offset == 0 ? 0 : 1) }
    }

    /// The map as a reader sees it: pre-order from the root, skipping the
    /// inside of collapsed branches, then each floating branch the same way
    /// with its floating topic at depth 1, the level it is drawn at.
    public func visibleOutline() -> [OutlineItem] {
        var result: [OutlineItem] = []
        var visited: Set<NodeID> = []
        var stack = topLevelStack()
        while let (id, depth) = stack.popLast() {
            guard let node = nodes[id], visited.insert(id).inserted else { continue }
            let children = childIDs(of: id)
            result.append(OutlineItem(nodeID: id, depth: depth, hasChildren: !children.isEmpty))
            if !node.isCollapsed {
                stack.append(contentsOf: children.reversed().map { ($0, depth + 1) })
            }
        }
        return result
    }
}

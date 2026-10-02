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

    /// The map as a reader sees it: pre-order from the root, skipping the
    /// inside of collapsed branches.
    public func visibleOutline() -> [OutlineItem] {
        guard let rootID = map.rootNodeID, nodes[rootID] != nil else { return [] }
        var result: [OutlineItem] = []
        var visited: Set<NodeID> = []
        var stack: [(id: NodeID, depth: Int)] = [(rootID, 0)]
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

import Foundation
import MindMapDomain

/// Something wrong with a graph's structure. Commands never produce these;
/// they appear in data that arrived through sync or an old bug, and
/// `GraphRepair` fixes them.
public enum GraphIssue: Hashable, Sendable {
    /// The map has nodes but no root, or its root ID points to nothing.
    case missingRoot
    case rootHasParent(NodeID)
    /// The top of a branch that does not reach the root: its parent is missing,
    /// or it has no parent and is not the root.
    case detachedBranch(NodeID)
    /// A node whose parent chain loops back on itself, for example after two
    /// devices each moved one node under the other.
    case cycle(NodeID)
    case danglingEdge(EdgeID)
    case selfLoopEdge(EdgeID)
    /// A tag link whose topic is gone. A link whose tag is missing is not an
    /// issue: the tag may still be on its way from another device.
    case danglingTagLink(NodeTagID)
    /// A second link between the same topic and tag; the oldest is kept.
    case duplicateTagLink(NodeTagID)
    /// A map tag whose key equals an older map tag's, from two devices
    /// creating it offline. Shared tags are checked by the library.
    case duplicateTag(TagID)
    /// A boundary whose ends are not a run of siblings under its parent.
    case invalidGroup(GroupID)
}

public enum GraphValidator {
    public static func validate(_ state: GraphState) -> Set<GraphIssue> {
        var issues: Set<GraphIssue> = []

        let root = state.root
        if root == nil, !(state.isEmpty && state.map.rootNodeID == nil) {
            issues.insert(.missingRoot)
        }
        if let root, root.parentID != nil {
            issues.insert(.rootHasParent(root.id))
        }

        let reachable = reachableNodes(in: state)
        let unreachable = Set(state.nodes.keys).subtracting(reachable)
        for id in unreachable {
            // A node whose parent exists is only unreachable because that parent
            // is; report the top of the branch, not every node in it.
            if let parentID = state.nodes[id]?.parentID, state.nodes[parentID] != nil { continue }
            issues.insert(.detachedBranch(id))
        }
        for id in cycleMembers(in: state, among: unreachable) {
            issues.insert(.cycle(id))
        }

        for edge in state.edges.values {
            if state.nodes[edge.sourceNodeID] == nil || state.nodes[edge.targetNodeID] == nil {
                issues.insert(.danglingEdge(edge.id))
            } else if edge.sourceNodeID == edge.targetNodeID {
                issues.insert(.selfLoopEdge(edge.id))
            }
        }
        issues.formUnion(organizationIssues(in: state))
        return issues
    }

    static func organizationIssues(in state: GraphState) -> Set<GraphIssue> {
        var issues: Set<GraphIssue> = []
        var seenLinks: Set<TagLinkKey> = []
        for link in state.nodeTags.values.sorted(by: oldestFirst) {
            if state.nodes[link.nodeID] == nil {
                issues.insert(.danglingTagLink(link.id))
            } else if !seenLinks.insert(TagLinkKey(nodeID: link.nodeID, tagID: link.tagID)).inserted {
                issues.insert(.duplicateTagLink(link.id))
            }
        }
        var seenKeys: Set<String> = []
        for tag in state.tags.values.sorted(by: oldestFirst) where tag.mapID == state.map.id {
            if !seenKeys.insert(tag.key).inserted {
                issues.insert(.duplicateTag(tag.id))
            }
        }
        // A kind this build does not know is hidden and left as it is.
        for group in state.groups.values where group.kind == .boundary && state.members(of: group) == nil {
            issues.insert(.invalidGroup(group.id))
        }
        return issues
    }

    struct TagLinkKey: Hashable {
        let nodeID: NodeID
        let tagID: TagID
    }

    static func oldestFirst(_ lhs: MindNodeTag, _ rhs: MindNodeTag) -> Bool {
        (lhs.createdAt, lhs.id) < (rhs.createdAt, rhs.id)
    }

    static func oldestFirst(_ lhs: MindTag, _ rhs: MindTag) -> Bool {
        (lhs.createdAt, lhs.id) < (rhs.createdAt, rhs.id)
    }

    private static func reachableNodes(in state: GraphState) -> Set<NodeID> {
        guard let rootID = state.root?.id else { return [] }
        var reachable: Set<NodeID> = [rootID]
        var queue = [rootID]
        while let id = queue.popLast() {
            for child in state.childIDs(of: id) where reachable.insert(child).inserted {
                queue.append(child)
            }
        }
        return reachable
    }

    /// Nodes that sit on a parent loop. Every unreachable node's parent is also
    /// unreachable or absent, so following parents from one either ends at a
    /// branch top or comes back around a loop.
    static func cycleMembers(in state: GraphState, among candidates: Set<NodeID>) -> Set<NodeID> {
        var members: Set<NodeID> = []
        var finished: Set<NodeID> = []
        for start in candidates where !finished.contains(start) {
            var path: [NodeID] = []
            var position: [NodeID: Int] = [:]
            var current: NodeID? = start
            while let id = current, candidates.contains(id), !finished.contains(id) {
                if let index = position[id] {
                    members.formUnion(path[index...])
                    break
                }
                position[id] = path.count
                path.append(id)
                current = state.nodes[id]?.parentID
            }
            finished.formUnion(path)
        }
        return members
    }
}

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
    /// or it has no parent, is not the root and has no position. A parentless
    /// topic with a position is a floating topic, not an issue.
    case detachedBranch(NodeID)
    /// A position on a topic that has a parent, or on the root: only a
    /// floating topic has one, so the tree wins and it is cleared.
    case strayPosition(NodeID)
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
    /// A boundary or summary whose ends are not a run of siblings under its parent.
    case invalidGroup(GroupID)
    /// A summary whose topic is under another parent, is one of the run's
    /// ends, is named by an older summary, or is not set. The topic stays.
    case invalidSummary(GroupID)
    /// An image whose topic is gone.
    case danglingImage(ImageID)
    /// A second image on one topic, from two devices; the newest is kept.
    case duplicateImage(ImageID)
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
        for node in state.nodes.values where node.position != nil && (node.parentID != nil || node.id == root?.id) {
            issues.insert(.strayPosition(node.id))
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
        for group in state.groups.values where group.kind.isRun && state.members(of: group) == nil {
            issues.insert(.invalidGroup(group.id))
        }
        for id in invalidSummaries(in: state) {
            issues.insert(.invalidSummary(id))
        }
        for image in state.images.values where state.nodes[image.nodeID] == nil {
            issues.insert(.danglingImage(image.id))
        }
        for id in duplicateImages(in: state) {
            issues.insert(.duplicateImage(id))
        }
        return issues
    }

    /// A summary naming a topic that is not loaded is not an issue: the topic
    /// may still be syncing, and repair deletes the group once it is too old.
    static func invalidSummaries(in state: GraphState) -> [GroupID] {
        var claimed: Set<NodeID> = []
        var invalid: [GroupID] = []
        let summaries = state.groups.values
            .filter { $0.kind == .summary }
            .sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
        for group in summaries {
            guard let topicID = group.summaryNodeID else {
                invalid.append(group.id)
                continue
            }
            guard let topic = state.nodes[topicID] else { continue }
            let isEnd = topicID == group.firstNodeID || topicID == group.lastNodeID
            if topic.parentID != group.parentNodeID || isEnd || !claimed.insert(topicID).inserted {
                invalid.append(group.id)
            }
        }
        return invalid
    }

    /// Every image on a topic but the newest (by `createdAt`, then ID).
    static func duplicateImages(in state: GraphState) -> [ImageID] {
        let byNode = Dictionary(grouping: state.images.values.filter { state.nodes[$0.nodeID] != nil }, by: \.nodeID)
        return byNode.values.flatMap { images in
            images.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }.dropLast().map(\.id)
        }.sorted()
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

    /// From the root and from every floating topic.
    private static func reachableNodes(in state: GraphState) -> Set<NodeID> {
        guard let rootID = state.root?.id else { return [] }
        let starts = [rootID] + state.floatingTopicIDs
        var reachable = Set(starts)
        var queue = starts
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

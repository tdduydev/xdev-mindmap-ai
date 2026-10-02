import Foundation
import MindMapDomain

/// Keeps boundaries valid while topics move. Boundaries are positional (a run
/// of siblings from `firstNodeID` to `lastNodeID`), so only a change to an
/// endpoint needs fixing; a topic added inside the run joins it on its own.
extension GraphTransaction {
    /// The boundaries a topic ends, as they were before it was reordered.
    struct GroupReorder {
        let nodeID: NodeID
        let parentID: NodeID
        /// Each affected group with its members before the move.
        let groups: [(id: GroupID, members: [NodeID])]
    }

    /// The topic leaves its parent (deleted or moved away): every boundary it
    /// ends moves that end inward to the nearest member still in the run, and
    /// a boundary left with no member is deleted.
    mutating func detachFromGroups(_ node: MindNode) throws {
        guard let parentID = node.parentID else { return }
        for group in endedGroups(by: node.id, under: parentID) {
            guard let members = state.members(of: group) else { continue }
            let remaining = members.filter { $0 != node.id }
            if let first = remaining.first, let last = remaining.last {
                try updateGroup(group.id) { group in
                    group.firstNodeID = first
                    group.lastNodeID = last
                }
            } else {
                try removeGroup(group.id)
            }
        }
    }

    func groupReorder(for node: MindNode) -> GroupReorder? {
        guard let parentID = node.parentID else { return nil }
        let groups = endedGroups(by: node.id, under: parentID).compactMap { group in
            state.members(of: group).map { (id: group.id, members: $0) }
        }
        return groups.isEmpty ? nil : GroupReorder(nodeID: node.id, parentID: parentID, groups: groups)
    }

    /// After an endpoint moved among its siblings. Moved within its own run, the
    /// boundary keeps the same members and its ends become the outermost of
    /// them. Moved out of the run, the end stays with the topic, and the run
    /// becomes the siblings between the two ends (swapped if needed).
    mutating func finishGroupReorder(_ reorder: GroupReorder) throws {
        let siblings = state.childIDs(of: reorder.parentID)
        let position = Dictionary(uniqueKeysWithValues: siblings.enumerated().map { ($1, $0) })
        guard let moved = position[reorder.nodeID] else { return }
        for (id, members) in reorder.groups {
            guard state.groups[id] != nil else { continue }
            let others = members.filter { $0 != reorder.nodeID }.compactMap { position[$0] }
            let staysInside = others.min().map { $0 < moved } == true && others.max().map { $0 > moved } == true
            let ends = staysInside
                ? members.compactMap { position[$0] }
                : [state.groups[id]?.firstNodeID, state.groups[id]?.lastNodeID].compactMap { $0.flatMap { position[$0] } }
            guard let low = ends.min(), let high = ends.max() else { continue }
            try updateGroup(id) { group in
                group.firstNodeID = siblings[low]
                group.lastNodeID = siblings[high]
            }
        }
    }

    private func endedGroups(by nodeID: NodeID, under parentID: NodeID) -> [MindGroup] {
        state.groups(under: parentID).filter { $0.firstNodeID == nodeID || $0.lastNodeID == nodeID }
    }
}

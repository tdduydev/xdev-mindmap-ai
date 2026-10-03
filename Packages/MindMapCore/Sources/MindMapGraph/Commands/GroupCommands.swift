import Foundation
import MindMapDomain

/// Frames a run of adjacent siblings, from one topic to another, with a
/// boundary. Ends may be given in either order.
///
/// Refuses the central topic, ends under different parents, a run another
/// boundary already frames, and a run that crosses another boundary under the
/// same parent (A–C with B–D). Nesting is fine.
public struct AddGroupCommand: GraphCommand {
    /// Chosen up front so the caller can select or rename the new boundary.
    public let groupID: GroupID
    public let firstNodeID: NodeID
    public let lastNodeID: NodeID
    public let title: String?
    public let color: TopicColor?
    public let origin: NodeOrigin

    public init(
        groupID: GroupID = GroupID(),
        from firstNodeID: NodeID,
        to lastNodeID: NodeID? = nil,
        title: String? = nil,
        color: TopicColor? = nil,
        origin: NodeOrigin = .user
    ) {
        self.groupID = groupID
        self.firstNodeID = firstNodeID
        self.lastNodeID = lastNodeID ?? firstNodeID
        self.title = title
        self.color = color
        self.origin = origin
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        let run = try Self.validRun(from: firstNodeID, to: lastNodeID, kind: .boundary, in: transaction.state)
        try transaction.insertGroup(MindGroup(
            id: groupID,
            mapID: transaction.state.map.id,
            parentNodeID: run.parentID,
            firstNodeID: run.firstID,
            lastNodeID: run.lastID,
            title: Self.cleaned(title),
            color: color,
            origin: origin,
            createdAt: transaction.now
        ))
    }

    /// The run between two siblings, in display order, checked against the
    /// other groups of the same kind under that parent. A boundary and a
    /// summary over the same or crossing runs are fine: one frames, the other
    /// brackets, and they never share a line.
    static func validRun(
        from firstNodeID: NodeID,
        to lastNodeID: NodeID,
        kind: GroupKind,
        in state: GraphState
    ) throws -> (parentID: NodeID, firstID: NodeID, lastID: NodeID) {
        guard let first = state.node(firstNodeID) else { throw GraphError.nodeNotFound(firstNodeID) }
        guard let last = state.node(lastNodeID) else { throw GraphError.nodeNotFound(lastNodeID) }
        guard let parentID = first.parentID, last.parentID != nil else { throw GraphError.cannotGroupRoot }
        guard last.parentID == parentID else { throw GraphError.notSiblings(lastNodeID) }

        // A summary topic is never a member of a run under its parent.
        let siblings = state.runSiblingIDs(of: parentID)
        guard let a = siblings.firstIndex(of: firstNodeID), let b = siblings.firstIndex(of: lastNodeID) else {
            throw GraphError.notSiblings(lastNodeID)
        }
        let run = min(a, b)...max(a, b)

        for other in state.groups(under: parentID) where other.kind == kind {
            guard let members = state.members(of: other),
                  let start = members.first.flatMap(siblings.firstIndex), let end = members.last.flatMap(siblings.firstIndex)
            else { continue }
            if start == run.lowerBound, end == run.upperBound { throw GraphError.groupAlreadyCoversRun(other.id) }
            let nested = (run.contains(start) && run.contains(end)) || ((start...end).contains(run.lowerBound) && (start...end).contains(run.upperBound))
            if run.overlaps(start...end), !nested { throw GraphError.groupsWouldCross(other.id) }
        }
        return (parentID, siblings[run.lowerBound], siblings[run.upperBound])
    }

    /// Trimmed; blank is no title.
    static func cleaned(_ title: String?) -> String? {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

/// Renames or recolours a boundary: "Rename Boundary".
public struct UpdateGroupCommand: GraphCommand {
    public let groupID: GroupID
    public let title: FieldChange<String?>
    public let color: FieldChange<TopicColor?>

    public init(groupID: GroupID, title: FieldChange<String?> = .keep, color: FieldChange<TopicColor?> = .keep) {
        self.groupID = groupID
        self.title = title
        self.color = color
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        let title = title.map(AddGroupCommand.cleaned)
        try transaction.updateGroup(groupID) { group in
            title.apply(to: &group.title)
            color.apply(to: &group.color)
        }
    }
}

/// Removes a boundary; the topics it framed stay.
public struct RemoveGroupCommand: GraphCommand {
    public let groupID: GroupID

    public init(groupID: GroupID) {
        self.groupID = groupID
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        try transaction.removeGroup(groupID)
    }
}

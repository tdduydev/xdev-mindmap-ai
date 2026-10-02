import Foundation
import MindMapDomain

/// Why a graph command was refused. The graph is unchanged when one is thrown.
public enum GraphError: Error, Hashable, Sendable {
    case nodeNotFound(NodeID)
    case nodeAlreadyExists(NodeID)
    case edgeNotFound(EdgeID)
    case edgeAlreadyExists(EdgeID)
    case belongsToAnotherMap
    case rootAlreadyExists
    case rootHasNoSiblings
    case cannotMoveRoot
    case wouldCreateCycle(node: NodeID, newParent: NodeID)
    /// A `before`/`after` anchor that is not a child of the target parent.
    case invalidPlacementAnchor(NodeID)
    /// Promoting a child of the root would make it the root's sibling.
    case alreadyTopLevel(NodeID)
    /// Demoting needs a sibling right before the node to become its parent.
    case noPreviousSibling(NodeID)
    /// Merging only joins topics under the same parent.
    case notSiblings(NodeID)
    case cannotLinkToItself(NodeID)
    case tagNotFound(TagID)
    case tagAlreadyExists(TagID)
    case nodeTagNotFound(NodeTagID)
    case nodeTagAlreadyExists(NodeTagID)
    /// Empty after trimming, or longer than `MindTag.maximumNameLength`.
    case invalidTagName
    /// Another tag of the same scope already has this name's key.
    case tagNameTaken(TagID)
    /// Shared tags are library data: they change through the repository, not
    /// through one map's undo history.
    case sharedTagIsLibraryData(TagID)
    case groupNotFound(GroupID)
    case groupAlreadyExists(GroupID)
    /// The central topic has no siblings to frame.
    case cannotGroupRoot
    /// An existing boundary already frames exactly this run.
    case groupAlreadyCoversRun(GroupID)
    /// The run would overlap an existing boundary without one containing the other.
    case groupsWouldCross(GroupID)
    case imageNotFound(ImageID)
    case imageAlreadyExists(ImageID)
    /// A topic has at most one image; this one is already on it.
    case nodeHasImage(ImageID)
    /// The graph is structurally broken: given to the engine that way, or left
    /// that way by a command, whose result was then discarded.
    case invalidGraph(Set<GraphIssue>)
}

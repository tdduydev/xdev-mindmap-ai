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
    /// The graph is structurally broken: given to the engine that way, or left
    /// that way by a command, whose result was then discarded.
    case invalidGraph(Set<GraphIssue>)
}

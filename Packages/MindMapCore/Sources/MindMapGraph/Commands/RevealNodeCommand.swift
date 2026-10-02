import Foundation
import MindMapDomain

/// Opens every collapsed branch above a topic, so the topic shows in the
/// outline and on the canvas. Find uses it to show a match hidden inside a
/// collapsed branch. Already visible topics change nothing and add no undo step.
public struct RevealNodeCommand: GraphCommand {
    public let nodeID: NodeID

    public init(nodeID: NodeID) {
        self.nodeID = nodeID
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        let state = transaction.state
        guard state.node(nodeID) != nil else { throw GraphError.nodeNotFound(nodeID) }
        for ancestorID in state.ancestors(of: nodeID) where state.node(ancestorID)?.isCollapsed == true {
            try transaction.updateNode(ancestorID) { $0.isCollapsed = false }
        }
    }

    /// Whether some branch above the topic is collapsed.
    public static func isHidden(_ id: NodeID, in state: GraphState) -> Bool {
        state.ancestors(of: id).contains { state.node($0)?.isCollapsed == true }
    }
}

import Foundation
import MindMapDomain

/// Deletes nodes together with their branches and every edge that touches them.
///
/// Takes several IDs so a multi-selection is one undo step. A selected node
/// inside another selected branch is simply deleted with that branch.
public struct DeleteNodeCommand: GraphCommand {
    public let nodeIDs: [NodeID]

    public init(nodeIDs: [NodeID]) {
        self.nodeIDs = nodeIDs
    }

    public init(nodeID: NodeID) {
        self.init(nodeIDs: [nodeID])
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        var doomed: Set<NodeID> = []
        for id in nodeIDs {
            guard transaction.state.node(id) != nil else { throw GraphError.nodeNotFound(id) }
            guard !doomed.contains(id) else { continue }
            doomed.insert(id)
            doomed.formUnion(transaction.state.descendants(of: id))
        }

        let doomedEdges = transaction.state.edges.values.filter {
            doomed.contains($0.sourceNodeID) || doomed.contains($0.targetNodeID)
        }
        for edge in doomedEdges {
            try transaction.removeEdge(edge.id)
        }
        for id in doomed {
            try transaction.removeNode(id)
        }

        if let rootID = transaction.state.map.rootNodeID, doomed.contains(rootID) {
            transaction.updateMap { $0.rootNodeID = nil }
        }
    }
}

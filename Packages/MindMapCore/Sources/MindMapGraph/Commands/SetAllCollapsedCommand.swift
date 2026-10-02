import Foundation
import MindMapDomain

/// Collapses or expands every branch of the map as one undo step.
///
/// Collapsing keeps the root open, so the map reads as its main branches rather
/// than a single topic. Only topics with children are touched: a leaf's flag
/// has no visible effect, and leaving it alone keeps the change set small.
public struct SetAllCollapsedCommand: GraphCommand {
    public let isCollapsed: Bool

    public init(isCollapsed: Bool) {
        self.isCollapsed = isCollapsed
    }

    public static let collapseAll = SetAllCollapsedCommand(isCollapsed: true)
    public static let expandAll = SetAllCollapsedCommand(isCollapsed: false)

    public func execute(in transaction: inout GraphTransaction) throws {
        let state = transaction.state
        let rootID = state.map.rootNodeID
        for node in state.nodes.values where !state.childIDs(of: node.id).isEmpty {
            let target = node.id == rootID ? false : isCollapsed
            guard node.isCollapsed != target else { continue }
            try transaction.updateNode(node.id) { $0.isCollapsed = target }
        }
    }
}

import Foundation
import MindMapDomain

/// Sets or removes the callout of one or many topics (FR-ORG-30): one undo
/// step, "Add Callout", "Edit Callout" or "Remove Callout" as the session
/// names it. Text is normalized with `MindNode.normalizedCallout`, so blank
/// text removes the callout; setting the same text changes nothing.
///
/// Deleting a topic needs no command of its own: the callout is a field of the
/// node, so it goes, comes back on undo and syncs with it.
public struct SetCalloutCommand: GraphCommand {
    public let nodeIDs: [NodeID]
    public let text: String?

    public init(nodeIDs: [NodeID], text: String?) {
        self.nodeIDs = nodeIDs
        self.text = text
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        let callout = text.flatMap(MindNode.normalizedCallout)
        for id in nodeIDs {
            try transaction.updateNode(id) { $0.callout = callout }
        }
    }
}

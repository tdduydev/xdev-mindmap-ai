import Foundation
import MindMapDomain

/// Splits a topic whose title has several lines into one topic per line.
///
/// The first line stays in the original topic, which keeps its ID, children,
/// note and links, so anything pointing at it still does. Each further line
/// becomes a new sibling right after it, in order. Blank lines are skipped, and
/// a title with one line is left alone.
public struct SplitNodeCommand: GraphCommand {
    public let nodeID: NodeID

    public init(nodeID: NodeID) {
        self.nodeID = nodeID
    }

    /// The topics a title splits into; one line means no split.
    public static func lines(of title: String) -> [String] {
        title.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        guard let node = transaction.state.node(nodeID) else { throw GraphError.nodeNotFound(nodeID) }
        let lines = Self.lines(of: node.title)
        guard lines.count > 1, let first = lines.first else { return }
        guard let parentID = node.parentID else { throw GraphError.rootHasNoSiblings }

        try transaction.updateNode(nodeID) { $0.title = first }
        var previous = nodeID
        for line in lines.dropFirst() {
            let id = NodeID()
            let sortOrder = try transaction.sortOrder(for: .after(previous), under: parentID)
            try transaction.insertNode(MindNode(
                id: id,
                mapID: node.mapID,
                parentID: parentID,
                title: line,
                sortOrder: sortOrder,
                nodeType: node.nodeType,
                metadata: node.metadata,
                createdAt: transaction.now
            ))
            previous = id
        }
    }
}

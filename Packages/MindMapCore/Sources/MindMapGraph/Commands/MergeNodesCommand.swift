import Foundation
import MindMapDomain

/// Folds sibling topics into one: the first selected topic stays, the others go.
///
/// Nothing the user wrote is lost. Children of the merged topics move under the
/// survivor, after its own children, in the order given. The survivor keeps its
/// title; each merged topic's title and note are appended to the survivor's note
/// as a paragraph. Cross-links are moved to the survivor, and a link that would
/// end up joining the survivor to itself, or repeat an existing link of the same
/// kind, is removed. Tags of the merged topics move to the survivor too, and so
/// does the first merged topic's image when the survivor has none.
public struct MergeNodesCommand: GraphCommand {
    public let survivorID: NodeID
    public let mergedIDs: [NodeID]

    public init(into survivorID: NodeID, merging mergedIDs: [NodeID]) {
        self.survivorID = survivorID
        self.mergedIDs = mergedIDs
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        let state = transaction.state
        guard let survivor = state.node(survivorID) else { throw GraphError.nodeNotFound(survivorID) }

        var seen: Set<NodeID> = [survivorID]
        var merged: [MindNode] = []
        for id in mergedIDs where seen.insert(id).inserted {
            guard let node = state.node(id) else { throw GraphError.nodeNotFound(id) }
            merged.append(node)
        }
        guard !merged.isEmpty else { return }
        guard survivor.parentID != nil else { throw GraphError.rootHasNoSiblings }
        for node in merged where node.parentID != survivor.parentID {
            throw GraphError.notSiblings(node.id)
        }

        for node in merged {
            for childID in state.childIDs(of: node.id) {
                let sortOrder = try transaction.sortOrder(for: .last, under: survivorID, excluding: childID)
                try transaction.updateNode(childID) { child in
                    child.parentID = survivorID
                    child.sortOrder = sortOrder
                }
            }
        }

        let note = Self.mergedNote(survivor: survivor, merged: merged)
        let gainedChildren = merged.contains { !state.childIDs(of: $0.id).isEmpty }
        // A topic holds one link: the survivor keeps its own, else takes the first merged one's.
        let link = survivor.link ?? merged.lazy.compactMap(\.link).first
        try transaction.updateNode(survivorID) { node in
            node.note = note
            node.link = link
            // Children moved into a collapsed topic would vanish from view.
            if gainedChildren { node.isCollapsed = false }
        }

        try rewireEdges(of: Set(merged.map(\.id)), in: &transaction)
        try moveTags(of: merged.map(\.id), in: &transaction)
        let current = transaction.state
        if current.image(of: survivorID) == nil,
           let image = merged.lazy.compactMap({ current.image(of: $0.id) }).first {
            // Moved, not copied: the record and its stored file stay as they are.
            try transaction.updateImage(image.id) { $0.nodeID = survivorID }
        }

        for node in merged {
            try transaction.removeNode(node.id)
        }
    }

    private func rewireEdges(of mergedIDs: Set<NodeID>, in transaction: inout GraphTransaction) throws {
        struct LinkKey: Hashable {
            let source: NodeID
            let target: NodeID
            let type: EdgeType
        }
        func remapped(_ id: NodeID) -> NodeID { mergedIDs.contains(id) ? survivorID : id }

        var touched: [MindEdge] = []
        var existing: Set<LinkKey> = []
        for edge in transaction.state.edges.values {
            if mergedIDs.contains(edge.sourceNodeID) || mergedIDs.contains(edge.targetNodeID) {
                touched.append(edge)
            } else {
                existing.insert(LinkKey(source: edge.sourceNodeID, target: edge.targetNodeID, type: edge.edgeType))
            }
        }

        // Oldest first, so which duplicate survives does not depend on dictionary order.
        for edge in touched.sorted(by: { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }) {
            let key = LinkKey(source: remapped(edge.sourceNodeID), target: remapped(edge.targetNodeID), type: edge.edgeType)
            if key.source == key.target || !existing.insert(key).inserted {
                try transaction.removeEdge(edge.id)
            } else {
                try transaction.updateEdge(edge.id) { edge in
                    edge.sourceNodeID = key.source
                    edge.targetNodeID = key.target
                }
            }
        }
    }

    private func moveTags(of mergedIDs: [NodeID], in transaction: inout GraphTransaction) throws {
        var present = Set(transaction.state.nodeTags.values.filter { $0.nodeID == survivorID }.map(\.tagID))
        let moving = transaction.state.nodeTags.values
            .filter { mergedIDs.contains($0.nodeID) }
            .sorted(by: GraphValidator.oldestFirst)
        for link in moving where present.insert(link.tagID).inserted {
            try transaction.updateNodeTag(link.id) { $0.nodeID = survivorID }
        }
        // Links left on the merged topics go with them in `removeNode`.
    }

    private static func mergedNote(survivor: MindNode, merged: [MindNode]) -> String? {
        func trimmed(_ text: String?) -> String {
            (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let added = merged
            .map { [trimmed($0.title), trimmed($0.note)].filter { !$0.isEmpty }.joined(separator: "\n") }
            .filter { !$0.isEmpty }
        guard !added.isEmpty else { return survivor.note }
        let own = trimmed(survivor.note).isEmpty ? [] : [survivor.note ?? ""]
        return (own + added).joined(separator: "\n\n")
    }
}

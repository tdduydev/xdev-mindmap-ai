import Foundation
import MindMapDomain
import MindMapGraph
@testable import MindMapInterchange

/// A draft as indented text, two spaces per level, with notes in brackets:
///
///     Plan [why]
///       Goals
extension OutlineDraft {
    var outline: String {
        items.map { item in
            String(repeating: "  ", count: item.depth) + item.title + (item.note.map { " [\($0)]" } ?? "")
        }
        .joined(separator: "\n")
    }
}

extension GraphState {
    /// The whole map as indented text, in the same shape as `OutlineDraft.outline`.
    var outline: String {
        guard let rootID = map.rootNodeID else { return "" }
        return (try? OutlineWalk.nodes(of: self, from: rootID))?
            .map { node, depth in
                String(repeating: "  ", count: depth) + node.title + (node.note.map { " [\($0)]" } ?? "")
            }
            .joined(separator: "\n") ?? ""
    }

    func firstNode(titled title: String) -> MindNode? {
        nodes.values.first { $0.title == title }
    }
}

/// Content equality that ignores the map's "last edited" time, which every
/// step (undo included) moves forward on purpose.
func sameContent(_ lhs: GraphState, _ rhs: GraphState) -> Bool {
    var leftMap = lhs.map
    leftMap.updatedAt = rhs.map.updatedAt
    return leftMap == rhs.map && lhs.nodes == rhs.nodes && lhs.edges == rhs.edges
}

let fixedDate = Date(timeIntervalSinceReferenceDate: 800_000_000)

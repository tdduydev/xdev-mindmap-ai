import Foundation
import MindMapDomain

/// Where a node goes among the children of its parent.
public enum ChildPlacement: Hashable, Sendable {
    case first
    case last
    case before(NodeID)
    case after(NodeID)
}

extension GraphTransaction {
    /// An order key for a node placed under `parentID`.
    ///
    /// Keys are midpoints between neighbours. Repeated inserts at one spot halve
    /// the gap each time and run out of `Double` precision after about 50
    /// inserts, so when no key fits the siblings are renumbered first. That
    /// renumbering is recorded like any other change and undone with it.
    mutating func sortOrder(
        for placement: ChildPlacement,
        under parentID: NodeID,
        excluding movingID: NodeID? = nil
    ) throws -> Double {
        if let key = try proposedSortOrder(for: placement, under: parentID, excluding: movingID) {
            return key
        }
        try renumberChildren(of: parentID, excluding: movingID)
        guard let key = try proposedSortOrder(for: placement, under: parentID, excluding: movingID) else {
            preconditionFailure("Siblings one apart always leave room for a midpoint")
        }
        return key
    }

    private func proposedSortOrder(
        for placement: ChildPlacement,
        under parentID: NodeID,
        excluding movingID: NodeID?
    ) throws -> Double? {
        let siblings = state.children(of: parentID).filter { $0.id != movingID }
        let keys = siblings.map(\.sortOrder)

        switch placement {
        case .first:
            return keys.first.map { $0 - 1 } ?? 0
        case .last:
            return keys.last.map { $0 + 1 } ?? 0
        case .before(let anchor):
            guard let index = siblings.firstIndex(where: { $0.id == anchor }) else {
                throw GraphError.invalidPlacementAnchor(anchor)
            }
            return index == 0 ? keys[index] - 1 : Self.midpoint(keys[index - 1], keys[index])
        case .after(let anchor):
            guard let index = siblings.firstIndex(where: { $0.id == anchor }) else {
                throw GraphError.invalidPlacementAnchor(anchor)
            }
            return index == keys.count - 1 ? keys[index] + 1 : Self.midpoint(keys[index], keys[index + 1])
        }
    }

    private mutating func renumberChildren(of parentID: NodeID, excluding movingID: NodeID?) throws {
        let siblings = state.childIDs(of: parentID).filter { $0 != movingID }
        for (index, id) in siblings.enumerated() {
            try updateNode(id) { $0.sortOrder = Double(index) }
        }
    }

    /// Nil when no `Double` lies strictly between the two keys.
    private static func midpoint(_ lower: Double, _ upper: Double) -> Double? {
        let middle = lower + (upper - lower) / 2
        return middle > lower && middle < upper ? middle : nil
    }
}

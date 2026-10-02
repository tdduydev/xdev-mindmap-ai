import Foundation
import MindMapDomain

extension GraphTransaction {
    /// Points every link of one tag at another. Where a topic already has the
    /// target tag, the older of the two links is kept, the same choice repair
    /// makes for duplicate links, so merging on two devices agrees.
    mutating func moveTagLinks(from oldTagID: TagID, to newTagID: TagID) throws {
        guard oldTagID != newTagID else { return }
        let moving = state.nodeTags.values.filter { $0.tagID == oldTagID }.sorted(by: GraphValidator.oldestFirst)
        for link in moving {
            let existing = state.nodeTags.values.first { $0.nodeID == link.nodeID && $0.tagID == newTagID }
            if let existing {
                if GraphValidator.oldestFirst(existing, link) {
                    try removeNodeTag(link.id)
                    continue
                }
                try removeNodeTag(existing.id)
            }
            try updateNodeTag(link.id) { $0.tagID = newTagID }
        }
    }

    /// Sort order for a new map tag: after the map's other tags.
    func nextTagSortOrder() -> Double {
        let orders = state.tags.values.filter { $0.mapID == state.map.id }.map(\.sortOrder)
        return orders.max().map { $0 + 1 } ?? 0
    }
}

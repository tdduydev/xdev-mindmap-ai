import Foundation
import MindMapDomain

extension GraphState {
    /// The map's own tags in their list order.
    public var mapTags: [MindTag] {
        tags.values
            .filter { $0.mapID == map.id }
            .sorted { ($0.sortOrder, $0.createdAt, $0.id) < ($1.sortOrder, $1.createdAt, $1.id) }
    }

    /// The library's tags, by name. They have no order of their own in a map.
    public var sharedTags: [MindTag] {
        tags.values
            .filter(\.isShared)
            .sorted { lhs, rhs in
                let order = lhs.name.localizedStandardCompare(rhs.name)
                return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
            }
    }

    /// How many topics carry each tag. Links whose topic or tag is missing
    /// (still syncing) are not counted.
    public func tagUseCounts() -> [TagID: Int] {
        var counts: [TagID: Int] = [:]
        for link in nodeTags.values where nodes[link.nodeID] != nil && tags[link.tagID] != nil {
            counts[link.tagID, default: 0] += 1
        }
        return counts
    }

    /// Topics that carry the tag, in no particular order.
    public func nodeIDs(taggedWith tagID: TagID) -> Set<NodeID> {
        Set(nodeTags.values.filter { $0.tagID == tagID && nodes[$0.nodeID] != nil }.map(\.nodeID))
    }
}

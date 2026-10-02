import Foundation
import MindMapDomain
import MindMapGraph

/// Find in one open map.
public enum MapFind {
    /// Topics whose title or note holds every word of the query, top to bottom
    /// as the outline reads with every branch open, so Find Next walks the map
    /// in reading order, collapsed branches included.
    public static func matches(_ query: SearchQuery, in state: GraphState) -> [NodeID] {
        guard !query.isEmpty, let rootID = state.map.rootNodeID, state.node(rootID) != nil else { return [] }
        return ([rootID] + state.descendants(of: rootID)).filter { id in
            guard let node = state.node(id) else { return false }
            return query.matches(node.title) || node.note.map { query.matches($0) } == true
        }
    }
}

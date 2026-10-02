import Foundation
import MindMapDomain

extension GraphState {
    /// A new map whose root topic carries the map's title, ready to type into.
    /// Templates will build on this: they are graphs, not screens.
    public static func newMap(id: MapID = MapID(), title: String, now: Date = .now) -> GraphState {
        let rootID = NodeID()
        let map = MindMap(id: id, title: title, rootNodeID: rootID, createdAt: now)
        let root = MindNode(id: rootID, mapID: id, parentID: nil, title: title, createdAt: now)
        return GraphState(map: map, nodes: [root], edges: [])
    }
}

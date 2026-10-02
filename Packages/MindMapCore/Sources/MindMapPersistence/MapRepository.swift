import Foundation
import MindMapDomain
import MindMapGraph

/// Where maps live. Features talk to this protocol, never to SwiftData, so the
/// store can change and tests can use an in-memory one.
public protocol MapRepository: Sendable {
    /// Every map, most recently edited first. Nodes are not loaded.
    func fetchMaps() async throws -> [MindMap]

    /// Nil when the map does not exist, for example after another device deleted it.
    func loadGraph(for mapID: MapID) async throws -> GraphState?

    /// Stores a whole new graph: a new map, a template or an import.
    func create(_ graph: GraphState) async throws

    /// Writes only the records in `changes`, plus the map itself.
    func save(_ changes: GraphChangeSet, map: MindMap) async throws

    /// Map-level fields edited outside the editor, such as favorite or title.
    func updateMap(_ map: MindMap) async throws

    func deleteMap(_ mapID: MapID) async throws
}

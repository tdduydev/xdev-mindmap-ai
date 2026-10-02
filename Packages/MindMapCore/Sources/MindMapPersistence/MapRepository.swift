import Foundation
import MindMapDomain
import MindMapGraph

public enum MapRepositoryChange: Sendable, Equatable {
    case updated(MapID)
    case deleted(MapID)
    /// Another context or process changed the store; consumers should fetch again.
    case refresh
}

/// Where maps live. Features talk to this protocol, never to SwiftData, so the
/// store can change and tests can use an in-memory one.
public protocol MapRepository: Sendable {
    /// Changes after subscription. Consumers fetch their own current snapshot first.
    func changes() async -> AsyncStream<MapRepositoryChange>
    /// Every map, most recently edited first. Nodes are not loaded.
    func fetchMaps() async throws -> [MindMap]

    /// Nil when the map does not exist, for example after another device deleted it.
    func loadGraph(for mapID: MapID) async throws -> GraphState?

    /// Stores a whole new graph: a new map, a template or an import.
    func create(_ graph: GraphState) async throws

    /// Writes only the records in `changes`, plus the map's graph fields (title,
    /// root, edit time, theme, layout). Library flags such as favorite are left
    /// alone, so an editor holding an older copy of the map cannot reset them.
    func save(_ changes: GraphChangeSet, map: MindMap) async throws

    /// Marking a map as a favorite is not an edit: it does not move `updatedAt`.
    func setFavorite(_ isFavorite: Bool, for mapID: MapID) async throws

    func deleteMap(_ mapID: MapID) async throws
}

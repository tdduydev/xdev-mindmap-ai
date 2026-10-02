import Foundation
import MindMapDomain
import MindMapGraph

/// What changed in the store, as the library needs to know it.
public enum MapRepositoryChange: Sendable, Equatable {
    /// This repository stored a map: created, edited or marked as a favorite.
    /// Carries the summary as stored, favorite flag included.
    case saved(MindMap)
    case deleted(MapID)
    /// Something other than this repository wrote to the store (another
    /// context, another process, later iCloud). Which maps changed is not
    /// known, so a consumer fetches its list again.
    case storeChanged
}

/// Where maps live. Features talk to this protocol, never to SwiftData, so the
/// store can change and tests can use an in-memory one.
public protocol MapRepository: Sendable {
    /// Every change committed after this call returns, in commit order, until
    /// the stream's task ends. Each window subscribes before its first fetch,
    /// so a write cannot fall between the fetch and the subscription.
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

    /// The title and note of every topic, by map, for library search. Empty
    /// titles and notes are left out.
    func fetchTopicTexts() async throws -> [MapID: [String]]
}

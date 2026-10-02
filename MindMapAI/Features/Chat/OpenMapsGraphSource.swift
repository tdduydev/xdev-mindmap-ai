import Foundation
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import MindMapQuery

/// Where the chat (and later the MCP server) reads maps: the editor's live
/// graph for a map that is open, so an answer matches what the window shows
/// rather than the last save, and the store for the rest.
nonisolated struct OpenMapsGraphSource: GraphSource {
    let openMaps: OpenMaps
    let repository: any MapRepository

    func graph(for mapID: MapID) async throws -> GraphState? {
        if let live = await openMaps.liveGraph(for: mapID) { return live }
        return try await repository.loadGraph(for: mapID)
    }

    func openMapIDs() async -> Set<MapID> {
        await openMaps.openMapIDs
    }
}

extension AppEnvironment {
    /// The reads the chat's tools make.
    var mapQueries: MapQueries {
        MapQueries(repository: repository, graphs: OpenMapsGraphSource(openMaps: openMaps, repository: repository))
    }
}

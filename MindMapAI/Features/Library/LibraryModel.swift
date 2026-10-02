import Foundation
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import Observation
import OSLog

/// The list of maps. Holds summaries only; a map's nodes load when it opens.
@Observable
final class LibraryModel {
    enum Failure: Hashable {
        case load
        case save
    }

    private(set) var maps: [MindMap] = []
    private(set) var hasLoaded = false
    var failure: Failure?

    @ObservationIgnored private let repository: any MapRepository

    init(repository: any MapRepository) {
        self.repository = repository
    }

    func maps(in section: LibrarySection) -> [MindMap] {
        section.maps(from: maps)
    }

    func load() async {
        do {
            maps = try await repository.fetchMaps()
        } catch {
            Log.persistence.error("Loading the library failed: \(error.localizedDescription, privacy: .public)")
            failure = .load
        }
        hasLoaded = true
    }

    /// Creates a map whose root topic carries its title and returns its ID, so the caller can open it.
    func createMap() async -> MapID? {
        let graph = GraphState.newMap(title: String(localized: "Untitled Map"))
        do {
            try await repository.create(graph)
            maps.append(graph.map)
            return graph.map.id
        } catch {
            Log.persistence.error("Creating a map failed: \(error.localizedDescription, privacy: .public)")
            failure = .save
            return nil
        }
    }

    func delete(_ map: MindMap) async {
        do {
            try await repository.deleteMap(map.id)
            maps.removeAll { $0.id == map.id }
        } catch {
            Log.persistence.error("Deleting a map failed: \(error.localizedDescription, privacy: .public)")
            failure = .save
        }
    }

    func toggleFavorite(_ map: MindMap) async {
        let isFavorite = !map.isFavorite
        do {
            try await repository.setFavorite(isFavorite, for: map.id)
            if let index = maps.firstIndex(where: { $0.id == map.id }) {
                maps[index].isFavorite = isFavorite
            }
        } catch {
            Log.persistence.error("Saving a favorite failed: \(error.localizedDescription, privacy: .public)")
            failure = .save
        }
    }

    /// The editor saved a change to `map`. The favorite flag stays as the
    /// library knows it: the editor's copy may predate a change made here.
    func didChange(_ map: MindMap) {
        guard let index = maps.firstIndex(where: { $0.id == map.id }) else { return }
        var updated = map
        updated.isFavorite = maps[index].isFavorite
        maps[index] = updated
    }
}

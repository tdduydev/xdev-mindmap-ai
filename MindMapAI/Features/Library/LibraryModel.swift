import Foundation
import MindMapDomain
import MindMapGraph
import MindMapIntents
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
    /// Keeps Spotlight's list of map titles in step with the library (FR-SYS-04).
    @ObservationIgnored private let searchIndex: (any MapSearchIndex)?

    init(repository: any MapRepository, searchIndex: (any MapSearchIndex)? = nil) {
        self.repository = repository
        self.searchIndex = searchIndex
    }

    func maps(in section: LibrarySection) -> [MindMap] {
        section.maps(from: maps)
    }

    /// Also called when the app comes back to the foreground: the Share
    /// Extension and the intents may have added or changed maps meanwhile.
    func load() async {
        do {
            let previous = hasLoaded ? maps : nil
            maps = try await repository.fetchMaps()
            await reindex(from: previous)
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
            await searchIndex?.update(graph.map)
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
            await searchIndex?.remove(map.id)
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
        let renamed = maps[index].title != map.title
        var updated = map
        updated.isFavorite = maps[index].isFavorite
        maps[index] = updated
        if renamed, let searchIndex {
            Task { await searchIndex.update(updated) }
        }
    }

    /// The first load rebuilds the whole index, which also drops maps deleted
    /// while the app was closed; later loads touch only what changed.
    private func reindex(from previous: [MindMap]?) async {
        guard let searchIndex else { return }
        guard let previous else {
            await searchIndex.replaceAll(with: maps)
            return
        }
        let before = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0.title) })
        let current = Set(maps.map(\.id))
        for map in maps where before[map.id] != map.title {
            await searchIndex.update(map)
        }
        for id in before.keys where !current.contains(id) {
            await searchIndex.remove(id)
        }
    }
}

import Foundation
import MindMapDomain
import MindMapGraph
import MindMapIntents
import MindMapPersistence
import MindMapSearch
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

    /// What the search field holds. Searching runs in `search()`, which the view
    /// calls whenever this or `searchGeneration` changes.
    var searchText = ""
    private(set) var searchResults = LibrarySearchResults.empty
    /// The query `searchResults` answers, so the view can tell "no results"
    /// from "not searched yet".
    private(set) var searchedQuery: SearchQuery?
    /// Moves on whenever a map changes, so an open search runs again.
    private(set) var searchGeneration = 0

    @ObservationIgnored private let repository: any MapRepository
    @ObservationIgnored private var searchIndex: LibrarySearchIndex?
    /// Keeps Spotlight's list of map titles in step with the library (FR-SYS-04).
    @ObservationIgnored private let spotlightIndex: (any MapSearchIndex)?

    init(repository: any MapRepository, spotlightIndex: (any MapSearchIndex)? = nil) {
        self.repository = repository
        self.spotlightIndex = spotlightIndex
    }

    func maps(in section: LibrarySection) -> [MindMap] {
        section.maps(from: maps)
    }

    struct SearchRow: Identifiable, Hashable {
        let map: MindMap
        let match: LibrarySearchMatch
        var id: MapID { map.id }
    }

    var isSearching: Bool { !SearchQuery(searchText).isEmpty }

    /// The section's maps that match the search, maps matching by title first.
    func searchRows(in section: LibrarySection) -> [SearchRow] {
        let maps = maps(in: section)
        let byID = Dictionary(maps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return searchResults.ranked(maps.map(\.id)).compactMap { hit in
            byID[hit.mapID].map { SearchRow(map: $0, match: hit.match) }
        }
    }

    /// Runs the current search. The index of every map's text is built on the
    /// first search after a change, off the main actor.
    func search() async {
        let query = SearchQuery(searchText)
        guard !query.isEmpty else {
            searchResults = .empty
            searchedQuery = nil
            return
        }
        let index: LibrarySearchIndex
        if let searchIndex {
            index = searchIndex
        } else {
            let generation = searchGeneration
            do {
                let texts = try await repository.fetchTopicTexts()
                let documents = maps.map { map in
                    MapSearchDocument(mapID: map.id, title: map.title, topicTexts: texts[map.id] ?? [])
                }
                index = await LibrarySearchIndex.build(documents: documents)
            } catch {
                Log.persistence.error("Loading text for search failed: \(error.localizedDescription, privacy: .public)")
                failure = .load
                return
            }
            // A map changed while the index was built; the next run builds it again.
            if generation == searchGeneration { searchIndex = index }
        }
        let results = await index.searchInBackground(query)
        guard !Task.isCancelled else { return }
        searchResults = results
        searchedQuery = query
    }

    private func invalidateSearch() {
        searchIndex = nil
        searchGeneration += 1
    }

    /// Also called when the app comes back to the foreground: the Share
    /// Extension and the intents may have added or changed maps meanwhile.
    func load() async {
        do {
            let previous = hasLoaded ? maps : nil
            maps = try await repository.fetchMaps()
            invalidateSearch()
            await reindex(from: previous)
        } catch {
            Log.persistence.error("Loading the library failed: \(error.localizedDescription, privacy: .public)")
            failure = .load
        }
        hasLoaded = true
    }

    /// Keeps this window's list current for as long as its view is on screen,
    /// without polling. Every window shares one repository, so an edit in one
    /// window reaches the others here; writes from outside the repository
    /// arrive as `.storeChanged`. Subscribing before the first fetch means a
    /// write cannot fall between the two.
    func observeChanges() async {
        let changes = await repository.changes()
        await load()
        for await change in changes {
            await apply(change)
        }
    }

    func apply(_ change: MapRepositoryChange) async {
        switch change {
        case .saved(let map):
            let renamed = maps.first { $0.id == map.id }?.title != map.title
            show(map)
            invalidateSearch()
            if renamed { await spotlightIndex?.update(map) }
        case .deleted(let id):
            maps.removeAll { $0.id == id }
            invalidateSearch()
            await spotlightIndex?.remove(id)
        case .storeChanged:
            await load()
        }
    }

    /// Creates a map whose root topic carries its title and returns its ID, so the caller can open it.
    func createMap() async -> MapID? {
        await createMap(GraphState.newMap(title: String(localized: "Untitled Map")))
    }

    /// Stores a map built elsewhere, such as an imported file, and returns its ID.
    func createMap(_ graph: GraphState) async -> MapID? {
        do {
            try await repository.create(graph)
            // The change stream may have delivered it already.
            show(graph.map)
            invalidateSearch()
            await spotlightIndex?.update(graph.map)
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
            invalidateSearch()
            await spotlightIndex?.remove(map.id)
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

    /// Adds or replaces a stored summary. An editor reports each edit before it
    /// is stored, so a summary from an earlier save can arrive after a newer
    /// edit; it must not roll the title back. The favorite flag is the
    /// store's either way, since the editor never sets it.
    private func show(_ map: MindMap) {
        guard let index = maps.firstIndex(where: { $0.id == map.id }) else {
            maps.append(map)
            return
        }
        if map.updatedAt >= maps[index].updatedAt {
            maps[index] = map
        } else {
            maps[index].isFavorite = map.isFavorite
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
        invalidateSearch()
        if renamed, let spotlightIndex {
            Task { await spotlightIndex.update(updated) }
        }
    }

    /// The first load rebuilds the whole index, which also drops maps deleted
    /// while the app was closed; later loads touch only what changed.
    private func reindex(from previous: [MindMap]?) async {
        guard let spotlightIndex else { return }
        guard let previous else {
            await spotlightIndex.replaceAll(with: maps)
            return
        }
        let before = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0.title) })
        let current = Set(maps.map(\.id))
        for map in maps where before[map.id] != map.title {
            await spotlightIndex.update(map)
        }
        for id in before.keys where !current.contains(id) {
            await spotlightIndex.remove(id)
        }
    }
}

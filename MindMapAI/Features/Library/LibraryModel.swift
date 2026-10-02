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

    /// Live maps. Everything that offers maps (sections, search, Spotlight)
    /// reads this list, so a deleted map cannot show up there.
    private(set) var maps: [MindMap] = []
    /// Maps in Recently Deleted (FR-LIB-11), only for that section.
    private(set) var deletedMaps: [MindMap] = []
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
    @ObservationIgnored private let clock: () -> Date

    init(repository: any MapRepository, spotlightIndex: (any MapSearchIndex)? = nil, clock: @escaping () -> Date = { .now }) {
        self.repository = repository
        self.spotlightIndex = spotlightIndex
        self.clock = clock
    }

    func maps(in section: LibrarySection) -> [MindMap] {
        section.maps(from: section == .recentlyDeleted ? deletedMaps : maps)
    }

    /// Whole days before a map in Recently Deleted goes for good.
    func daysLeft(for map: MindMap) -> Int? {
        map.deletedAt.map { RecentlyDeleted.daysLeft(deletedAt: $0, now: clock()) }
    }

    struct SearchRow: Identifiable, Hashable {
        let map: MindMap
        let match: LibrarySearchMatch
        var id: MapID { map.id }
    }

    var isSearching: Bool { !SearchQuery(searchText).isEmpty }

    /// The section's maps that match the search, maps matching by title first.
    /// Library search covers live maps only; inside Recently Deleted the field
    /// filters that section by title, so its maps never show up anywhere else.
    func searchRows(in section: LibrarySection) -> [SearchRow] {
        let maps = maps(in: section)
        if section == .recentlyDeleted {
            let query = SearchQuery(searchText)
            return maps.filter { query.matches($0.title) }.map { SearchRow(map: $0, match: .title) }
        }
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
        await purgeExpiredMaps()
        do {
            // Shared tags made on two devices offline merge here, as a map's
            // own tags do when it opens (docs/node-organization.md, *Sync and repair*).
            try await repository.repairSharedTags()
        } catch {
            // The library still loads; the duplicates stay until the next load.
            Log.persistence.error("Repairing shared tags failed: \(error.localizedDescription, privacy: .public)")
        }
        do {
            let previous = hasLoaded ? maps : nil
            maps = try await repository.fetchMaps()
            deletedMaps = try await repository.fetchDeletedMaps()
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
        case .saved(let map) where map.deletedAt != nil:
            await showDeleted(map)
        case .saved(let map):
            await showLive(map)
        case .deleted(let id):
            maps.removeAll { $0.id == id }
            deletedMaps.removeAll { $0.id == id }
            invalidateSearch()
            await spotlightIndex?.remove(id)
        case .storeChanged:
            await load()
        case .tagsChanged:
            // Library search matches tag names.
            invalidateSearch()
        }
    }

    /// Creates a map whose root topic carries its title and returns its ID, so
    /// the caller can open it. `theme` is Settings ▸ Theme for New Maps
    /// (`NewMapPreferences.theme`), resolved by the caller, which knows Pro.
    func createMap(theme: MindMapTheme = .standard) async -> MapID? {
        await createMap(GraphState.newMap(title: String(localized: "Untitled Map"), theme: theme))
    }

    /// Stores a map built elsewhere, such as an imported file, and returns its ID.
    /// `imageData` holds the bytes of its images (`MapArchive.imported`).
    func createMap(_ graph: GraphState, imageData: [ImageID: Data] = [:]) async -> MapID? {
        do {
            try await repository.create(graph, imageData: imageData)
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

    // MARK: Recently Deleted

    /// Moves a map to Recently Deleted (FR-LIB-04, FR-LIB-11). It can be
    /// restored, so there is no confirmation; Edit ▸ Undo Delete Map brings it
    /// back. Library data, not an edit, so it is not a `GraphCommand`.
    func delete(_ map: MindMap, undoManager: UndoManager? = nil) async {
        guard await perform(.delete, on: map.id) else { return }
        registerUndo(after: .delete, of: map.id, on: undoManager, actionName: String(localized: "Delete Map"))
    }

    func restore(_ map: MindMap, undoManager: UndoManager? = nil) async {
        guard await perform(.restore, on: map.id) else { return }
        registerUndo(after: .restore, of: map.id, on: undoManager, actionName: String(localized: "Restore Map"))
    }

    /// Deletes a map and all its topics for good, after the view has asked (DR-07).
    func deletePermanently(_ map: MindMap) async {
        do {
            try await repository.deleteMap(map.id)
            maps.removeAll { $0.id == map.id }
            deletedMaps.removeAll { $0.id == map.id }
            invalidateSearch()
            await spotlightIndex?.remove(map.id)
        } catch {
            Log.persistence.error("Deleting a map failed: \(error.localizedDescription, privacy: .public)")
            failure = .save
        }
    }

    /// Runs on every load, so maps past 30 days go when the app opens or comes
    /// back to the foreground (FR-LIB-11). Removing them from the lists and
    /// from Spotlight is left to the fetch that follows.
    private func purgeExpiredMaps() async {
        do {
            let purged = try await repository.purgeDeletedMaps(deletedBefore: RecentlyDeleted.cutoff(now: clock()))
            if !purged.isEmpty {
                Log.persistence.notice("Deleted \(purged.count, privacy: .public) maps past their time in Recently Deleted")
            }
        } catch {
            // The next load tries again; nothing the person did failed.
            Log.persistence.error("Emptying Recently Deleted failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private enum BinMove {
        case delete
        case restore

        var inverse: BinMove { self == .delete ? .restore : .delete }
    }

    /// False when the map is not where the move starts (already moved, or
    /// deleted for good since the undo step was registered) or the store failed.
    @discardableResult
    private func perform(_ move: BinMove, on id: MapID) async -> Bool {
        do {
            switch move {
            case .delete:
                guard var map = maps.first(where: { $0.id == id }) else { return false }
                let deletedAt = clock()
                try await repository.moveToRecentlyDeleted(id, at: deletedAt)
                map.deletedAt = deletedAt
                await showDeleted(map)
            case .restore:
                guard var map = deletedMaps.first(where: { $0.id == id }) else { return false }
                try await repository.restoreMap(id)
                map.deletedAt = nil
                await showLive(map)
            }
            return true
        } catch {
            Log.persistence.error("Moving a map to or from Recently Deleted failed: \(error.localizedDescription, privacy: .public)")
            failure = .save
            return false
        }
    }

    /// The undo step runs the inverse move. It registers its own inverse
    /// synchronously, inside the undo, so UndoManager files it as the redo;
    /// registered from the async task it would land on the undo stack instead.
    private func registerUndo(after move: BinMove, of id: MapID, on undoManager: UndoManager?, actionName: String) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { [weak undoManager] model in
            model.registerUndo(after: move.inverse, of: id, on: undoManager, actionName: actionName)
            Task { await model.perform(move.inverse, on: id) }
        }
        undoManager.setActionName(actionName)
    }

    /// A map that went to Recently Deleted, here or in another window.
    private func showDeleted(_ map: MindMap) async {
        let wasLive = maps.contains { $0.id == map.id }
        maps.removeAll { $0.id == map.id }
        if let index = deletedMaps.firstIndex(where: { $0.id == map.id }) {
            deletedMaps[index] = map
        } else {
            deletedMaps.append(map)
        }
        invalidateSearch()
        if wasLive { await spotlightIndex?.remove(map.id) }
    }

    /// A live map stored, or restored, here or in another window.
    private func showLive(_ map: MindMap) async {
        deletedMaps.removeAll { $0.id == map.id }
        // Also true for a map not in the list yet: new, or restored.
        let renamed = maps.first { $0.id == map.id }?.title != map.title
        show(map)
        invalidateSearch()
        if renamed { await spotlightIndex?.update(map) }
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

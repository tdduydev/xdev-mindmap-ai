import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import MindMapIntents
import MindMapPersistence
import Testing

/// FR-LIB-11, FR-LIB-04, DR-07: deleting a map moves it to Recently Deleted,
/// where it waits 30 days to be restored or deleted for good.
@Suite("Recently Deleted in the library")
struct RecentlyDeletedLibraryTests {
    final class Clock {
        var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    }

    actor RecordingIndex: MapSearchIndex {
        private(set) var titles: [MapID: String] = [:]

        func replaceAll(with maps: [MindMap]) {
            titles = Dictionary(uniqueKeysWithValues: maps.map { ($0.id, $0.title) })
        }

        func update(_ map: MindMap) { titles[map.id] = map.title }
        func remove(_ mapID: MapID) { titles[mapID] = nil }
    }

    let repository: SwiftDataMapRepository
    let clock = Clock()
    let index = RecordingIndex()
    let library: LibraryModel

    init() throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
        let clock = clock
        library = LibraryModel(repository: repository, spotlightIndex: index, clock: { clock.now })
    }

    @Test func deleteMovesTheMapToRecentlyDeleted() async throws {
        let kept = try #require(await library.createMap())
        let deleted = try #require(await library.createMap())

        await library.delete(try map(deleted))

        #expect(library.maps.map(\.id) == [kept])
        #expect(library.maps(in: .all).map(\.id) == [kept])
        #expect(library.maps(in: .recent).map(\.id) == [kept])
        #expect(library.maps(in: .recentlyDeleted).map(\.id) == [deleted])
        #expect(library.deletedMaps.first?.deletedAt == clock.now)
        #expect(library.daysLeft(for: try #require(library.deletedMaps.first)) == 30)
        // Still stored, topics and all, for Restore.
        #expect(try await repository.loadGraph(for: deleted)?.nodes.count == 1)

        let clock = clock
        let reloaded = LibraryModel(repository: repository, clock: { clock.now })
        await reloaded.load()
        #expect(reloaded.maps.map(\.id) == [kept])
        #expect(reloaded.deletedMaps.map(\.id) == [deleted])
    }

    @Test func restoreBringsTheMapBackWithItsFavorite() async throws {
        let id = try #require(await library.createMap())
        await library.toggleFavorite(try map(id))
        await library.delete(try map(id))
        #expect(library.maps(in: .favorites).isEmpty)

        await library.restore(try #require(library.deletedMaps.first))

        #expect(library.deletedMaps.isEmpty)
        #expect(library.maps(in: .favorites).map(\.id) == [id])
        #expect(try await repository.fetchMaps().first?.deletedAt == nil)
    }

    @Test func deletePermanentlyRemovesEveryRecord() async throws {
        let id = try #require(await library.createMap())
        await library.delete(try map(id))

        await library.deletePermanently(try #require(library.deletedMaps.first))

        #expect(library.deletedMaps.isEmpty)
        #expect(library.maps.isEmpty)
        #expect(try await repository.loadGraph(for: id) == nil)
    }

    /// Edit ▸ Undo Delete Map, then Redo, each one step.
    @Test func deleteUndoesAndRedoes() async throws {
        let undoManager = UndoManager()
        let id = try #require(await library.createMap())

        await library.delete(try map(id), undoManager: undoManager)
        #expect(undoManager.undoActionName == String(localized: "Delete Map"))

        undoManager.undo()
        try await until { library.maps.map(\.id) == [id] }
        #expect(library.deletedMaps.isEmpty)
        #expect(undoManager.canRedo)
        #expect(undoManager.redoActionName == String(localized: "Delete Map"))

        undoManager.redo()
        try await until { library.deletedMaps.map(\.id) == [id] }
        #expect(library.maps.isEmpty)
        #expect(undoManager.canUndo)
        #expect(try await repository.fetchDeletedMaps().map(\.id) == [id])
    }

    @Test func restoreUndoesAndRedoes() async throws {
        let undoManager = UndoManager()
        let id = try #require(await library.createMap())
        await library.delete(try map(id))

        await library.restore(try #require(library.deletedMaps.first), undoManager: undoManager)
        #expect(undoManager.undoActionName == String(localized: "Restore Map"))

        undoManager.undo()
        try await until { library.deletedMaps.map(\.id) == [id] }
        undoManager.redo()
        try await until { library.maps.map(\.id) == [id] }
        #expect(try await repository.fetchMaps().map(\.id) == [id])
    }

    /// Undo of a delete does nothing once the map is gone for good.
    @Test func undoAfterPermanentDeletionDoesNothing() async throws {
        let undoManager = UndoManager()
        let id = try #require(await library.createMap())
        await library.delete(try map(id), undoManager: undoManager)
        await library.deletePermanently(try #require(library.deletedMaps.first))

        undoManager.undo()
        try await Task.sleep(for: .milliseconds(50))

        #expect(library.maps.isEmpty)
        #expect(try await repository.loadGraph(for: id) == nil)
    }

    @Test func openingTheAppPurgesMapsOlderThanThirtyDays() async throws {
        let old = try #require(await library.createMap())
        await library.delete(try map(old))
        clock.now += 20 * 24 * 60 * 60
        let recent = try #require(await library.createMap())
        await library.delete(try map(recent))
        #expect(library.daysLeft(for: try #require(library.deletedMaps.first { $0.id == old })) == 10)

        clock.now += 10 * 24 * 60 * 60 + 1
        await library.load()

        #expect(library.deletedMaps.map(\.id) == [recent])
        #expect(try await repository.loadGraph(for: old) == nil)
        #expect(try await repository.loadGraph(for: recent) != nil)
    }

    @Test func searchSkipsDeletedMaps() async throws {
        let live = GraphState.newMap(title: "Plan live")
        let deleted = GraphState.newMap(title: "Plan deleted")
        try await repository.create(live)
        try await repository.create(deleted)
        await library.load()
        await library.delete(try map(deleted.map.id))

        library.searchText = "plan"
        await library.search()

        #expect(library.searchRows(in: .all).map(\.map.id) == [live.map.id])
        // Inside Recently Deleted the field filters that section by title.
        #expect(library.searchRows(in: .recentlyDeleted).map(\.map.id) == [deleted.map.id])
        library.searchText = "live"
        #expect(library.searchRows(in: .recentlyDeleted).isEmpty)
    }

    @Test func spotlightDropsDeletedMapsAndGetsRestoredOnesBack() async throws {
        let binned = GraphState.newMap(title: "Binned")
        try await repository.create(binned)
        try await repository.moveToRecentlyDeleted(binned.map.id, at: clock.now)
        let id = try #require(await library.createMap())

        await library.load()
        #expect(await index.titles[binned.map.id] == nil)
        #expect(await index.titles[id] != nil)

        await library.delete(try map(id))
        #expect(await index.titles[id] == nil)

        await library.restore(try #require(library.deletedMaps.first { $0.id == id }))
        #expect(await index.titles[id] != nil)
    }

    /// Every window has its own library on the one repository the app shares.
    @Test func otherWindowsFollowDeleteAndRestore() async throws {
        let observing = Task { await library.observeChanges() }
        defer { observing.cancel() }
        try await until { library.hasLoaded }
        let otherWindow = LibraryModel(repository: repository)
        let id = try #require(await otherWindow.createMap())
        try await until { library.maps.map(\.id) == [id] }

        await otherWindow.delete(try #require(otherWindow.maps.first))
        try await until { library.deletedMaps.map(\.id) == [id] }
        #expect(library.maps.isEmpty)

        await otherWindow.restore(try #require(otherWindow.deletedMaps.first))
        try await until { library.maps.map(\.id) == [id] }
        #expect(library.deletedMaps.isEmpty)
    }

    /// A window restored at launch can still name a map deleted since.
    @Test func editorDoesNotOpenADeletedMap() async throws {
        let id = try #require(await library.createMap())
        await library.delete(try map(id))

        let opening = await EditorSession.open(mapID: id, repository: repository, onMapChange: { _ in })

        guard case .recentlyDeleted = opening else {
            Issue.record("Expected .recentlyDeleted")
            return
        }
    }

    @Test func recentlyDeletedSectionListsNewestDeletionFirst() {
        let older = MindMap(title: "Older", deletedAt: Date(timeIntervalSinceReferenceDate: 1))
        let newer = MindMap(title: "Newer", deletedAt: Date(timeIntervalSinceReferenceDate: 2))

        #expect(LibrarySection.recentlyDeleted.maps(from: [older, newer]).map(\.title) == ["Newer", "Older"])
    }

    private func map(_ id: MapID) throws -> MindMap {
        try #require(library.maps.first { $0.id == id })
    }

    private func until(
        _ condition: () -> Bool,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("The library did not catch up", sourceLocation: sourceLocation)
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import Testing

@Suite("Library")
struct LibraryModelTests {
    let repository: SwiftDataMapRepository
    let library: LibraryModel

    init() throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
        library = LibraryModel(repository: repository)
    }

    @Test func startsEmptyAndLoaded() async {
        await library.load()

        #expect(library.hasLoaded)
        #expect(library.maps.isEmpty)
    }

    @Test func createdMapIsStoredWithARoot() async throws {
        let id = try #require(await library.createMap())

        let graph = try #require(try await repository.loadGraph(for: id))
        #expect(graph.root?.title == graph.map.title)
        #expect(library.maps.map(\.id) == [id])
    }

    @Test func favoritesAndDeletion() async throws {
        let kept = try #require(await library.createMap())
        let doomed = try #require(await library.createMap())
        let keptMap = try #require(library.maps.first { $0.id == kept })

        await library.toggleFavorite(keptMap)
        #expect(library.maps(in: .favorites).map(\.id) == [kept])

        let doomedMap = try #require(library.maps.first { $0.id == doomed })
        await library.delete(doomedMap)
        #expect(library.maps.map(\.id) == [kept])

        let reloaded = LibraryModel(repository: repository)
        await reloaded.load()
        #expect(reloaded.maps.map(\.id) == [kept])
        #expect(reloaded.maps.first?.isFavorite == true)
    }

    /// The editor's copy of a map can predate a favorite set in the library.
    @Test func editorUpdatesKeepTheLibraryFavorite() async throws {
        let id = try #require(await library.createMap())
        let original = try #require(library.maps.first)
        await library.toggleFavorite(original)

        var edited = original
        edited.title = "Renamed in editor"
        edited.isFavorite = false
        library.didChange(edited)

        let current = try #require(library.maps.first { $0.id == id })
        #expect(current.title == "Renamed in editor")
        #expect(current.isFavorite)
    }

    /// Every window has its own library on the one repository the app shares.
    @Test func followsChangesMadeInAnotherWindow() async throws {
        let observing = Task { await library.observeChanges() }
        defer { observing.cancel() }
        try await until { library.hasLoaded }
        let otherWindow = LibraryModel(repository: repository)

        let id = try #require(await otherWindow.createMap())
        try await until { library.maps.map(\.id) == [id] }

        await otherWindow.toggleFavorite(try #require(otherWindow.maps.first))
        try await until { library.maps.first?.isFavorite == true }

        guard case .ready(let editor) = await EditorSession.open(mapID: id, repository: repository, onMapChange: otherWindow.didChange) else {
            throw OpenFailed()
        }
        editor.renameMap(to: "Renamed elsewhere")
        await editor.flush()
        try await until { library.maps.first?.title == "Renamed elsewhere" }
        #expect(library.maps.first?.isFavorite == true)

        await otherWindow.delete(try #require(otherWindow.maps.first))
        try await until { library.maps.isEmpty }
    }

    /// A map created here arrives on the stream as well; it must be listed once.
    @Test func ownChangesAreNotListedTwice() async throws {
        let observing = Task { await library.observeChanges() }
        defer { observing.cancel() }
        try await until { library.hasLoaded }
        let otherWindow = LibraryModel(repository: repository)

        let own = try #require(await library.createMap())
        // Its change comes before this one, so once this one is applied, so is the first.
        let other = try #require(await otherWindow.createMap())
        try await until { library.maps.contains { $0.id == other } }

        #expect(library.maps.count == 2)
        #expect(Set(library.maps.map(\.id)) == [own, other])
    }

    /// A second repository on the same file stands in for another process.
    @Test func followsWritesFromOutsideTheRepository() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "library-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "maps.store")
        let here = LibraryModel(repository: try PersistenceController.makeRepository(at: .file(url)))
        let elsewhere = LibraryModel(repository: try PersistenceController.makeRepository(at: .file(url)))
        let observing = Task { await here.observeChanges() }
        defer { observing.cancel() }
        try await until { here.hasLoaded }

        let id = try #require(await elsewhere.createMap())

        try await until { here.maps.map(\.id) == [id] }
    }

    /// The editor reports an edit before saving it, so the summary of an
    /// earlier save can arrive after it.
    @Test func anOlderSummaryKeepsTheNewerTitle() async throws {
        _ = try #require(await library.createMap())
        let stored = try #require(library.maps.first)
        var edited = stored
        edited.title = "Still typing"
        edited.updatedAt = stored.updatedAt.addingTimeInterval(1)
        library.didChange(edited)

        var older = stored
        older.isFavorite = true
        await library.apply(.saved(older))

        #expect(library.maps.first?.title == "Still typing")
        #expect(library.maps.first?.isFavorite == true)
    }

    @Test func sectionsSortAndFilter() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let maps = [
            MindMap(title: "beta", createdAt: now.addingTimeInterval(-300)),
            MindMap(title: "Alpha", createdAt: now, isFavorite: true),
            MindMap(title: "Gamma", createdAt: now.addingTimeInterval(-100)),
        ]

        #expect(LibrarySection.all.maps(from: maps).map(\.title) == ["Alpha", "beta", "Gamma"])
        #expect(LibrarySection.recent.maps(from: maps).map(\.title) == ["Alpha", "Gamma", "beta"])
        #expect(LibrarySection.favorites.maps(from: maps).map(\.title) == ["Alpha"])
    }

    /// The library applies changes on its own task; this waits for one,
    /// recording a failure after a few seconds instead of hanging.
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

    private struct OpenFailed: Error {}
}

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
}

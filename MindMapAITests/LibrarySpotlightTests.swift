import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import MindMapIntents
import MindMapPersistence
import Testing

/// FR-SYS-04: Spotlight holds the title of every map, and nothing else.
@Suite("Library and Spotlight")
struct LibrarySpotlightTests {
    actor RecordingIndex: MapSearchIndex {
        private(set) var titles: [MapID: String] = [:]
        private(set) var replaceAllCount = 0

        func replaceAll(with maps: [MindMap]) {
            replaceAllCount += 1
            titles = Dictionary(uniqueKeysWithValues: maps.map { ($0.id, $0.title) })
        }

        func update(_ map: MindMap) { titles[map.id] = map.title }
        func remove(_ mapID: MapID) { titles[mapID] = nil }
    }

    let repository: SwiftDataMapRepository
    let index = RecordingIndex()
    let library: LibraryModel

    init() throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
        library = LibraryModel(repository: repository, searchIndex: index)
    }

    @Test func firstLoadIndexesEveryMap() async throws {
        let stored = GraphState.newMap(title: "Kế hoạch")
        try await repository.create(stored)

        await library.load()

        #expect(await index.titles == [stored.map.id: "Kế hoạch"])
        #expect(await index.replaceAllCount == 1)
    }

    @Test func createdAndDeletedMapsFollow() async throws {
        await library.load()
        let id = try #require(await library.createMap())
        #expect(await index.titles[id] != nil)

        let map = try #require(library.maps.first { $0.id == id })
        await library.delete(map)
        #expect(await index.titles[id] == nil)
    }

    /// Maps added by the Share Extension or an intent, or renamed elsewhere,
    /// show up when the app comes back and reloads.
    @Test func reloadIndexesOnlyWhatChanged() async throws {
        var engine = try GraphEngine(state: GraphState.newMap(title: "Old title"))
        try await repository.create(engine.state)
        let gone = GraphState.newMap(title: "Gone")
        try await repository.create(gone)
        await library.load()

        let changes = try engine.execute(RenameMapCommand(title: "New title"))
        try await repository.save(changes, map: engine.state.map)
        try await repository.deleteMap(gone.map.id)
        let shared = GraphState.newMap(title: "Shared")
        try await repository.create(shared)

        await library.load()

        #expect(await index.titles == [engine.state.map.id: "New title", shared.map.id: "Shared"])
        #expect(await index.replaceAllCount == 1)
    }
}

import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import MindMapIntents
import MindMapInterchange
import MindMapPersistence
import Testing

@Suite("Settings Data")
struct DataSettingsTests {
    @Test func emptyRecentlyDeletedRemovesEveryMapAndSpotlightEntry() async throws {
        let repository = try PersistenceController.makeRepository(at: .inMemory)
        let index = RecordingIndex()
        let model = DataSettingsModel(repository: repository, spotlightIndex: index)
        let graph = GraphState.newMap(title: "Deleted")
        try await repository.create(graph)
        try await repository.moveToRecentlyDeleted(graph.map.id, at: .now)

        await model.refresh()
        #expect(model.deletedCount == 1)
        await model.emptyRecentlyDeleted()
        #expect(model.deletedCount == 0)
        #expect(try await repository.loadGraph(for: graph.map.id) == nil)
        #expect(await index.removed.contains(graph.map.id))
    }

    @Test func allMapsExportAsSeparateRestorableArchives() async throws {
        let repository = try PersistenceController.makeRepository(at: .inMemory)
        let model = DataSettingsModel(repository: repository, spotlightIndex: NoSearchIndex())
        let first = GraphState.newMap(title: "Same")
        let second = GraphState.newMap(title: "Same")
        try await repository.create(first)
        try await repository.create(second)

        await model.prepareExport()
        let folder = try #require(model.exportFolder)
        #expect(folder.files.count == 2)
        for data in folder.files.values {
            let archive = try await MapArchive.decode(data)
            #expect(archive.graph.map.title == "Same")
        }
    }

    @Test func importingTheSameBackupTwiceKeepsTheOriginal() async throws {
        let repository = try PersistenceController.makeRepository(at: .inMemory)
        let model = DataSettingsModel(repository: repository, spotlightIndex: NoSearchIndex())
        let original = GraphState.newMap(title: "Original")
        try await repository.create(original)
        let data = try await MapArchive.exportData(original)
        let url = FileManager.default.temporaryDirectory.appending(path: "MM45-\(UUID().uuidString).json")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await model.importFiles(.success([url, url]))
        #expect(model.failure == nil)
        let maps = try await repository.fetchMaps()
        #expect(maps.count == 3)
        #expect(maps.contains { $0.id == original.map.id })
        #expect(Set(maps.map(\.id)).count == 3)
    }
}

private actor RecordingIndex: MapSearchIndex {
    private(set) var removed: [MapID] = []
    func replaceAll(with maps: [MindMap]) async {}
    func update(_ map: MindMap) async {}
    func remove(_ mapID: MapID) async { removed.append(mapID) }
}

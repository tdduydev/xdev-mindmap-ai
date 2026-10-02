import Foundation
import MindMapDomain
import MindMapGraph
@testable import MindMapPersistence
import SwiftData
import Testing

/// A missing change would leave `next()` waiting forever; the time limit turns that into a failure.
@Suite("Repository changes", .timeLimit(.minutes(1)))
struct ChangeStreamTests {
    @Test func ownWritesArriveInOrderAsStored() async throws {
        let repository = try PersistenceController.makeRepository(at: .inMemory)
        var changes = await repository.changes().makeAsyncIterator()
        var engine = try GraphEngine(state: GraphState.newMap(title: "Stream"))
        let created = engine.state.map

        try await repository.create(engine.state)
        try await repository.setFavorite(true, for: created.id)
        let root = try #require(created.rootNodeID)
        let edit = try engine.execute(AddNodeCommand(.child(of: root), title: "Child"))
        // The editor's copy still says "not a favorite"; the stored summary must not.
        try await repository.save(edit, map: engine.state.map)
        try await repository.deleteMap(created.id)

        var favorite = created
        favorite.isFavorite = true
        var edited = engine.state.map
        edited.isFavorite = true
        let received = [
            await changes.next(), await changes.next(), await changes.next(), await changes.next(),
        ]
        #expect(received == [.saved(created), .saved(favorite), .saved(edited), .deleted(created.id)])
    }

    /// Every window subscribes to the one repository the app shares.
    @Test func everySubscriberHearsEveryWrite() async throws {
        let repository = try PersistenceController.makeRepository(at: .inMemory)
        var first = await repository.changes().makeAsyncIterator()
        var second = await repository.changes().makeAsyncIterator()
        let graph = GraphState.newMap(title: "Shared")

        try await repository.create(graph)

        #expect(await first.next() == .saved(graph.map))
        #expect(await second.next() == .saved(graph.map))
    }

    /// The repository's own commits also raise remote-change notices; only
    /// someone else's may turn into `.storeChanged`.
    @Test func anotherContextOnTheStoreAsksForAFetch() async throws {
        let container = try PersistenceController.makeContainer(at: .inMemory)
        let repository = SwiftDataMapRepository(modelContainer: container)
        var changes = await repository.changes().makeAsyncIterator()
        let graph = GraphState.newMap(title: "Own")
        try await repository.create(graph)

        let context = ModelContext(container)
        let record = MapRecord(mapID: UUID())
        record.title = "Other context"
        context.insert(record)
        try context.save()

        #expect(await changes.next() == .saved(graph.map))
        #expect(await changes.next() == .storeChanged)
        #expect(try await repository.fetchMaps().map(\.title).sorted() == ["Other context", "Own"])
    }

    /// A second repository on the same file stands in for another process,
    /// such as a second copy of the app or, later, an iCloud import.
    @Test func anotherRepositoryOnTheFileAsksForAFetch() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "changes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "map.store")
        let here = try PersistenceController.makeRepository(at: .file(url))
        let elsewhere = try PersistenceController.makeRepository(at: .file(url))
        var engine = try GraphEngine(state: GraphState.newMap(title: "Before"))
        try await here.create(engine.state)
        #expect(try await here.fetchMaps().map(\.title) == ["Before"])
        var changes = await here.changes().makeAsyncIterator()

        let rename = try engine.execute(RenameMapCommand(title: "After"))
        try await elsewhere.save(rename, map: engine.state.map)

        #expect(await changes.next() == .storeChanged)
        // The record was already in this repository's context; the fetch must not return it stale.
        #expect(try await here.fetchMaps().map(\.title) == ["After"])
    }
}

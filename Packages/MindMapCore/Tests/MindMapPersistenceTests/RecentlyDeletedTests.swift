import Foundation
import MindMapDomain
import MindMapGraph
@testable import MindMapPersistence
import SwiftData
import Testing

@Suite("Recently Deleted", .timeLimit(.minutes(1)))
struct RecentlyDeletedTests {
    let container: ModelContainer
    let repository: SwiftDataMapRepository
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    init() throws {
        container = try PersistenceController.makeContainer(at: .inMemory)
        repository = SwiftDataMapRepository(modelContainer: container)
    }

    @Test func movedMapLeavesTheLiveListAndKeepsItsTopics() async throws {
        let kept = GraphState.newMap(title: "Kept")
        let deleted = GraphState.newMap(title: "Deleted")
        try await repository.create(kept)
        try await repository.create(deleted)

        try await repository.moveToRecentlyDeleted(deleted.map.id, at: now)

        #expect(try await repository.fetchMaps().map(\.id) == [kept.map.id])
        let inBin = try await repository.fetchDeletedMaps()
        #expect(inBin.map(\.id) == [deleted.map.id])
        #expect(inBin.first?.deletedAt == now)
        let loaded = try #require(try await repository.loadGraph(for: deleted.map.id))
        #expect(loaded.nodes == deleted.nodes)
        #expect(loaded.map.deletedAt == now)
    }

    @Test func restoredMapComesBackAsItWas() async throws {
        let graph = GraphState.newMap(title: "Back")
        try await repository.create(graph)
        try await repository.setFavorite(true, for: graph.map.id)

        try await repository.moveToRecentlyDeleted(graph.map.id, at: now)
        try await repository.restoreMap(graph.map.id)

        let maps = try await repository.fetchMaps()
        #expect(maps.map(\.id) == [graph.map.id])
        #expect(maps.first?.deletedAt == nil)
        #expect(maps.first?.isFavorite == true)
        #expect(maps.first?.updatedAt == graph.map.updatedAt)
        #expect(try await repository.fetchDeletedMaps().isEmpty)
    }

    @Test func deletedMapsListNewestDeletionFirst() async throws {
        let older = GraphState.newMap(title: "Older")
        let newer = GraphState.newMap(title: "Newer")
        try await repository.create(older)
        try await repository.create(newer)

        try await repository.moveToRecentlyDeleted(newer.map.id, at: now)
        try await repository.moveToRecentlyDeleted(older.map.id, at: now.addingTimeInterval(-60))

        #expect(try await repository.fetchDeletedMaps().map(\.title) == ["Newer", "Older"])
    }

    /// The editor of a map moved to the bin in another window keeps saving;
    /// its saves must not bring the map back.
    @Test func savingAnEditDoesNotRestore() async throws {
        var engine = try GraphEngine(state: GraphState.newMap(title: "Open"))
        try await repository.create(engine.state)
        try await repository.moveToRecentlyDeleted(engine.state.map.id, at: now)

        let root = try #require(engine.state.map.rootNodeID)
        let changes = try engine.execute(AddNodeCommand(.child(of: root), title: "Late"))
        try await repository.save(changes, map: engine.state.map)

        #expect(try await repository.fetchMaps().isEmpty)
        #expect(try await repository.fetchDeletedMaps().first?.deletedAt == now)
    }

    @Test func purgeDeletesOnlyMapsPastTheCutoff() async throws {
        let live = GraphState.newMap(title: "Live")
        let recent = GraphState.newMap(title: "Recent")
        let expired = GraphState.newMap(title: "Expired")
        for graph in [live, recent, expired] { try await repository.create(graph) }
        let cutoff = RecentlyDeleted.cutoff(now: now)
        try await repository.moveToRecentlyDeleted(recent.map.id, at: cutoff.addingTimeInterval(1))
        try await repository.moveToRecentlyDeleted(expired.map.id, at: cutoff.addingTimeInterval(-1))

        let purged = try await repository.purgeDeletedMaps(deletedBefore: cutoff)

        #expect(purged == [expired.map.id])
        #expect(try await repository.loadGraph(for: expired.map.id) == nil)
        #expect(try await repository.fetchDeletedMaps().map(\.id) == [recent.map.id])
        #expect(try await repository.fetchMaps().map(\.id) == [live.map.id])
        let expiredID = expired.map.id.rawValue
        let context = ModelContext(container)
        #expect(try context.fetchCount(FetchDescriptor<NodeRecord>(predicate: #Predicate { $0.mapID == expiredID })) == 0)
    }

    @Test func purgeWithNothingDueWritesNothing() async throws {
        try await repository.create(GraphState.newMap(title: "Live"))
        var changes = await repository.changes().makeAsyncIterator()

        #expect(try await repository.purgeDeletedMaps(deletedBefore: now).isEmpty)

        // The next change heard is this create, not a purge.
        let marker = GraphState.newMap(title: "Marker")
        try await repository.create(marker)
        #expect(await changes.next() == .saved(marker.map))
    }

    @Test func changesCarryTheDeletionDate() async throws {
        let graph = GraphState.newMap(title: "Stream")
        try await repository.create(graph)
        var changes = await repository.changes().makeAsyncIterator()

        try await repository.moveToRecentlyDeleted(graph.map.id, at: now)
        try await repository.restoreMap(graph.map.id)
        try await repository.moveToRecentlyDeleted(graph.map.id, at: now)
        try await repository.purgeDeletedMaps(deletedBefore: now.addingTimeInterval(1))

        var deleted = graph.map
        deleted.deletedAt = now
        let received = [await changes.next(), await changes.next(), await changes.next(), await changes.next()]
        #expect(received == [.saved(deleted), .saved(graph.map), .saved(deleted), .deleted(graph.map.id)])
    }

    @Test func daysLeftCountUp() {
        #expect(RecentlyDeleted.daysLeft(deletedAt: now, now: now) == 30)
        #expect(RecentlyDeleted.daysLeft(deletedAt: now, now: now.addingTimeInterval(60)) == 30)
        let lastHour = RecentlyDeleted.expiry(of: now).addingTimeInterval(-3600)
        #expect(RecentlyDeleted.daysLeft(deletedAt: now, now: lastHour) == 1)
        #expect(RecentlyDeleted.daysLeft(deletedAt: now, now: RecentlyDeleted.expiry(of: now)) == 0)
    }
}

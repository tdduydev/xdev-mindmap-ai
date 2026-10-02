import Foundation
import MindMapDomain
import MindMapGraph
import MindMapIntents
import MindMapPersistence
import Synchronization
import Testing

@Suite("Intent services")
struct MindMapIntentServicesTests {
    /// What the app was asked to do, recorded instead of done.
    final class Recorder: Sendable {
        let opened = Mutex<[MapID]>([])
        let clipboard = Mutex<String?>(nil)
    }

    actor RecordingIndex: MapSearchIndex {
        private(set) var indexed: [MapID: String] = [:]

        func replaceAll(with maps: [MindMap]) {
            indexed = Dictionary(uniqueKeysWithValues: maps.map { ($0.id, $0.title) })
        }

        func update(_ map: MindMap) { indexed[map.id] = map.title }
        func remove(_ mapID: MapID) { indexed[mapID] = nil }
    }

    let repository: SwiftDataMapRepository
    let recorder = Recorder()
    let index = RecordingIndex()
    let services: MindMapIntentServices

    init() throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
        let recorder = recorder
        services = MindMapIntentServices(
            repository: repository,
            index: index,
            untitledTitle: { "Untitled Map" },
            openMap: { id in recorder.opened.withLock { $0.append(id) } },
            readClipboard: { recorder.clipboard.withLock { $0 } }
        )
    }

    @Test func newMapIsCreatedIndexedAndOpened() async throws {
        let map = try await services.newMap(title: "  Roadmap ")
        #expect(map.title == "Roadmap")
        #expect(try await repository.fetchMaps().map(\.id) == [map.id])
        #expect(recorder.opened.withLock { $0 } == [map.id])
        #expect(await index.indexed[map.id] == "Roadmap")
    }

    @Test func newMapWithoutTitleIsUntitled() async throws {
        #expect(try await services.newMap(title: nil).title == "Untitled Map")
        #expect(try await services.newMap(title: "   ").title == "Untitled Map")
    }

    @Test func clipboardMarkdownBecomesAMap() async throws {
        recorder.clipboard.withLock { $0 = "# Trip\n- Flights\n- Hotel\n  - Hanoi" }
        let map = try await services.mapFromClipboard()
        let graph = try #require(try await repository.loadGraph(for: map.id))
        let rootID = try #require(graph.map.rootNodeID)
        #expect(map.title == "Trip")
        #expect(graph.children(of: rootID).map(\.title) == ["Flights", "Hotel"])
        #expect(recorder.opened.withLock { $0 } == [map.id])
    }

    @Test func emptyClipboardMakesNoMap() async throws {
        recorder.clipboard.withLock { $0 = " \n " }
        await #expect(throws: MindMapIntentServices.Failure.emptyClipboard) {
            try await services.mapFromClipboard()
        }
        #expect(try await repository.fetchMaps().isEmpty)
        #expect(recorder.opened.withLock { $0 }.isEmpty)
    }

    @Test func addIdeaDoesNotOpenTheApp() async throws {
        let map = try await services.newMap(title: "Plan")
        recorder.opened.withLock { $0 = [] }
        let updated = try await services.addIdea("Call the client", to: map.id)
        let graph = try #require(try await repository.loadGraph(for: map.id))
        let rootID = try #require(graph.map.rootNodeID)
        #expect(updated.id == map.id)
        #expect(graph.children(of: rootID).map(\.title) == ["Call the client"])
        #expect(recorder.opened.withLock { $0 }.isEmpty)
    }

    @Test func addIdeaReportsBlankAndMissing() async throws {
        await #expect(throws: MindMapIntentServices.Failure.emptyIdea) {
            try await services.addIdea(" ", to: nil)
        }
        await #expect(throws: MindMapIntentServices.Failure.mapNotFound) {
            try await services.addIdea("Idea", to: MapID())
        }
    }

    @Test func openRecentOpensTheLastEditedMap() async throws {
        try await repository.create(GraphState.newMap(title: "Older", now: Date(timeIntervalSince1970: 1)))
        let newer = GraphState.newMap(title: "Newer", now: Date(timeIntervalSince1970: 2))
        try await repository.create(newer)
        #expect(try await services.openRecent().id == newer.map.id)
        #expect(recorder.opened.withLock { $0 } == [newer.map.id])
    }

    @Test func openRecentWithNoMapsFails() async throws {
        await #expect(throws: MindMapIntentServices.Failure.noMaps) {
            try await services.openRecent()
        }
    }

    @Test func openingADeletedMapFails() async throws {
        await #expect(throws: MindMapIntentServices.Failure.mapNotFound) {
            try await services.open(MapID())
        }
        #expect(recorder.opened.withLock { $0 }.isEmpty)
    }

    @Test func queriesFindMapsByIDAndTitle() async throws {
        let plan = GraphState.newMap(title: "Kế hoạch quý", now: Date(timeIntervalSince1970: 1))
        let trip = GraphState.newMap(title: "Trip", now: Date(timeIntervalSince1970: 2))
        try await repository.create(plan)
        try await repository.create(trip)
        #expect(try await services.maps(withIDs: [plan.map.id, MapID(), trip.map.id]).map(\.id) == [plan.map.id, trip.map.id])
        #expect(try await services.maps(matching: "KE HOACH").map(\.id) == [plan.map.id])
        #expect(try await services.maps(matching: "").map(\.id) == [trip.map.id, plan.map.id])
        #expect(try await services.recentMaps(limit: 1).map(\.id) == [trip.map.id])
    }
}

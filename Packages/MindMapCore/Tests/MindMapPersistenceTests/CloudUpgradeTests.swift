import CoreData
import Foundation
import MindMapDomain
import MindMapGraph
@testable import MindMapPersistence
import SwiftData
import Testing

/// A 1.0 library (SchemaV3, written without CloudKit) when 1.1 turns sync on
/// (FR-SYN-08). CloudKit itself cannot run here: it stops a process without
/// the container entitlement. So these tests check what the mirroring
/// depends on: the same file, no migration, history kept, every map once.
/// That CloudKit then sends the old maps up is checked on devices
/// (cloudkit-sync.md, *Testing on real devices*).
@Suite("1.0 store going to iCloud")
struct CloudUpgradeTests {
    @Test func turningSyncOnOpensTheSameFile() throws {
        let store = try FixtureStore(copying: "V3")
        defer { store.remove() }
        let schema = Schema(versionedSchema: CurrentSchema.self)

        let local = try PersistenceController.configuration(at: .file(store.url), sync: .off, schema: schema)
        let cloud = try PersistenceController.configuration(at: .file(store.url), sync: .appContainer, schema: schema)

        #expect(local.url == cloud.url)
        #expect(local.name == cloud.name)
        #expect(String(describing: local.cloudKitDatabase) != String(describing: cloud.cloudKitDatabase))
    }

    /// The model CloudKit mirrors (the one `initializeCloudKitSchema`
    /// deployed) matches the 1.0 store as is, so opening it with mirroring
    /// needs no migration and no new file.
    @Test func v3StoreNeedsNoMigrationForTheMirroredModel() throws {
        let store = try FixtureStore(copying: "V3")
        defer { store.remove() }
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: CurrentSchema.models))

        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: store.url)

        #expect(model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata))
    }

    /// Mirroring needs persistent history. 1.0 kept it on, so the store
    /// opens with history tracking without Core Data dropping to read-only,
    /// and every record is there once.
    @Test func v3StoreOpensWithHistoryTrackingAndEveryRecordOnce() throws {
        let store = try FixtureStore(copying: "V3")
        defer { store.remove() }
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: CurrentSchema.models))
        let description = NSPersistentStoreDescription(url: store.url)
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        description.shouldAddStoreAsynchronously = false
        description.shouldMigrateStoreAutomatically = false
        description.shouldInferMappingModelAutomatically = false
        let container = NSPersistentContainer(name: "MindMapAI", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        var loadError: (any Error)?
        container.loadPersistentStores { _, error in loadError = error }
        defer {
            for loaded in container.persistentStoreCoordinator.persistentStores {
                try? container.persistentStoreCoordinator.remove(loaded)
            }
        }
        #expect(loadError == nil)

        let context = container.viewContext
        let request = NSPersistentHistoryChangeRequest.fetchHistory(after: nil as NSPersistentHistoryToken?)
        let history = try context.execute(request) as? NSPersistentHistoryResult
        let transactions = history?.result as? [NSPersistentHistoryTransaction] ?? []
        #expect(!transactions.isEmpty)

        let maps = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "MapRecord"))
        let mapIDs = maps.compactMap { $0.value(forKey: "mapID") as? UUID }
        #expect(Set(mapIDs) == [V3Fixture.mapID, V3Fixture.deletedMapID])
        #expect(mapIDs.count == 2)
        #expect(try context.count(for: NSFetchRequest<NSManagedObject>(entityName: "NodeRecord")) == 5)
    }

    /// Edits made in 1.1 before sync turns on (or while it is off) land in
    /// history too, so they go up with the rest once it is on.
    @Test func editsWhileSyncIsOffAreInHistory() async throws {
        let store = try FixtureStore(copying: "V3")
        defer { store.remove() }
        let container = try PersistenceController.makeContainer(at: .file(store.url), sync: .off)
        let before = try Self.transactionCount(in: container)
        let repository = SwiftDataMapRepository(modelContainer: container)

        try await repository.create(GraphState.newMap(title: "Written offline"))

        #expect(try Self.transactionCount(in: container) > before)
    }

    /// The same map sent up from two devices (a 1.0 library restored onto
    /// a second device) arrives as two records; the library shows it once,
    /// and the next save leaves one record.
    @Test func aMapThatArrivesTwiceIsListedOnce() async throws {
        let store = try FixtureStore(copying: "V3")
        defer { store.remove() }
        let container = try PersistenceController.makeContainer(at: .file(store.url), sync: .off)
        let context = ModelContext(container)
        let original = try #require(try context.fetch(FetchDescriptor<MapRecord>()).first { $0.mapID == V3Fixture.mapID })
        let copy = MapRecord(mapID: V3Fixture.mapID)
        copy.update(from: original.domainValue)
        context.insert(copy)
        let deletedOriginal = try #require(try context.fetch(FetchDescriptor<MapRecord>()).first { $0.mapID == V3Fixture.deletedMapID })
        let deletedCopy = MapRecord(mapID: V3Fixture.deletedMapID)
        deletedCopy.update(from: deletedOriginal.domainValue)
        context.insert(deletedCopy)
        try context.save()
        let repository = SwiftDataMapRepository(modelContainer: container)

        #expect(try await repository.fetchMaps().map(\.id) == [MapID(V3Fixture.mapID)])
        #expect(try await repository.fetchDeletedMaps().map(\.id) == [MapID(V3Fixture.deletedMapID)])

        var engine = try GraphEngine(state: try #require(try await repository.loadGraph(for: MapID(V3Fixture.mapID))))
        let changes = try engine.execute(UpdateNodeCommand(nodeID: NodeID(V3Fixture.childID), .title("Edited after sync")))
        try await repository.save(changes, map: engine.state.map)

        let mapID = V3Fixture.mapID
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<MapRecord>(predicate: #Predicate { $0.mapID == mapID })) == 1)
    }

    private static func transactionCount(in container: ModelContainer) throws -> Int {
        try ModelContext(container).fetchHistory(HistoryDescriptor<DefaultHistoryTransaction>()).count
    }
}

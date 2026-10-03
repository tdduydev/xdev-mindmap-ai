import CoreData
import Foundation
import SwiftData

/// Opens the app's store.
public enum PersistenceController {
    public enum Location: Sendable {
        /// The app's default store on this device.
        case standard
        case file(URL)
        /// The store shared with the Share Extension and the intents, in an App
        /// Group container (`AppGroup.containerURL()`). Opening it first moves a
        /// store left at `.standard` by an older build into it.
        case appGroup(containerURL: URL)
        /// Gone when the process ends; for tests and previews.
        case inMemory
    }

    /// Whether the store mirrors to iCloud (cloudkit-sync.md).
    public enum Sync: Sendable, Equatable {
        /// This device only: tests, previews, the Share Extension, a build
        /// without the iCloud entitlement, and sync turned off.
        case off
        /// Mirrors to the person's private CloudKit database. Only for a
        /// process signed with that container: CloudKit stops a process
        /// that asks for a container it is not entitled to.
        case privateDatabase(containerIdentifier: String)

        public static let appContainer = Sync.privateDatabase(containerIdentifier: CloudSyncContainer.identifier)

        var database: ModelConfiguration.CloudKitDatabase {
            switch self {
            case .off: .none
            case .privateDatabase(let identifier): .private(identifier)
            }
        }
    }

    /// The schema follows CloudKit's rules, so turning sync on or off needs no
    /// migration; the same file opens either way. Persistent history stays
    /// on in both, so what is written while sync is off goes up once it is on.
    public static func makeContainer(at location: Location = .standard, sync: Sync = .off) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let configuration = try configuration(at: location, sync: sync, schema: schema)
        return try ModelContainer(for: schema, migrationPlan: MindMapMigrationPlan.self, configurations: configuration)
    }

    /// Split from `makeContainer` so tests can check that turning sync on
    /// points at the store 1.0 wrote, without opening CloudKit (which stops
    /// an unentitled process).
    static func configuration(at location: Location, sync: Sync, schema: Schema) throws -> ModelConfiguration {
        let database = sync.database
        return switch location {
        case .standard:
            standardConfiguration(schema: schema, database: database)
        case .file(let url):
            ModelConfiguration("MindMapAI", schema: schema, url: url, cloudKitDatabase: database)
        case .appGroup(let containerURL):
            try sharedConfiguration(schema: schema, containerURL: containerURL, database: database)
        case .inMemory:
            ModelConfiguration("MindMapAI", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }
    }

    /// Where `.standard` keeps the store: the app's own container.
    public static var standardStoreURL: URL {
        standardConfiguration(schema: Schema(versionedSchema: CurrentSchema.self)).url
    }

    /// `.none`, not SwiftData's default `.automatic`: once the app has an App
    /// Group entitlement, `.automatic` would already point into the group, and
    /// the store an older build left in the app's own container would never be
    /// found and moved.
    private static func standardConfiguration(
        schema: Schema,
        database: ModelConfiguration.CloudKitDatabase = .none
    ) -> ModelConfiguration {
        ModelConfiguration("MindMapAI", schema: schema, groupContainer: .none, cloudKitDatabase: database)
    }

    private static func sharedConfiguration(
        schema: Schema,
        containerURL: URL,
        database: ModelConfiguration.CloudKitDatabase
    ) throws -> ModelConfiguration {
        let url = AppGroup.storeURL(in: containerURL)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try StoreRelocation.move(from: standardStoreURL, to: url)
        return ModelConfiguration("MindMapAI", schema: schema, url: url, cloudKitDatabase: database)
    }

    /// SwiftData has no `initializeCloudKitSchema`; Core Data does, on the
    /// same model. Run once from a development build signed for the container,
    /// so every record type and field exists in the development environment
    /// before it is deployed to production (FR-SYN-07). It writes test records
    /// to the private database and deletes them again; never call it in a
    /// shipped build.
    public static func initializeCloudKitSchema(containerIdentifier: String = CloudSyncContainer.identifier) throws {
        let types: [any PersistentModel.Type] = CurrentSchema.models
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: types) else {
            throw CloudKitSchemaError.modelUnavailable
        }
        // A throwaway store: the schema goes up, the person's maps stay out of it.
        let directory = FileManager.default.temporaryDirectory.appending(path: "MindMapAI-schema-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let description = NSPersistentStoreDescription(url: directory.appending(path: "Schema.store"))
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
        description.shouldAddStoreAsynchronously = false
        let container = NSPersistentCloudKitContainer(name: "MindMapAI", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        var loadError: (any Error)?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        try container.initializeCloudKitSchema()
        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
    }

    public enum CloudKitSchemaError: Error {
        case modelUnavailable
    }

    public static func makeRepository(at location: Location = .standard, sync: Sync = .off) throws -> SwiftDataMapRepository {
        SwiftDataMapRepository(modelContainer: try makeContainer(at: location, sync: sync))
    }
}

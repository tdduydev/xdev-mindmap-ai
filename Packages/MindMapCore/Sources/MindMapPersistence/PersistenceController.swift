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

    /// Sync stays off until CloudKit is switched on in its own phase; the
    /// schema already follows CloudKit's rules, so turning it on needs no migration.
    public static func makeContainer(at location: Location = .standard) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = switch location {
        case .standard:
            standardConfiguration(schema: schema)
        case .file(let url):
            ModelConfiguration("MindMapAI", schema: schema, url: url, cloudKitDatabase: .none)
        case .appGroup(let containerURL):
            try sharedConfiguration(schema: schema, containerURL: containerURL)
        case .inMemory:
            ModelConfiguration("MindMapAI", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, migrationPlan: MindMapMigrationPlan.self, configurations: configuration)
    }

    /// Where `.standard` keeps the store: the app's own container.
    public static var standardStoreURL: URL {
        standardConfiguration(schema: Schema(versionedSchema: SchemaV1.self)).url
    }

    /// `.none`, not SwiftData's default `.automatic`: once the app has an App
    /// Group entitlement, `.automatic` would already point into the group, and
    /// the store an older build left in the app's own container would never be
    /// found and moved.
    private static func standardConfiguration(schema: Schema) -> ModelConfiguration {
        ModelConfiguration("MindMapAI", schema: schema, groupContainer: .none, cloudKitDatabase: .none)
    }

    private static func sharedConfiguration(schema: Schema, containerURL: URL) throws -> ModelConfiguration {
        let url = AppGroup.storeURL(in: containerURL)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try StoreRelocation.move(from: standardStoreURL, to: url)
        return ModelConfiguration("MindMapAI", schema: schema, url: url, cloudKitDatabase: .none)
    }

    public static func makeRepository(at location: Location = .standard) throws -> SwiftDataMapRepository {
        SwiftDataMapRepository(modelContainer: try makeContainer(at: location))
    }
}

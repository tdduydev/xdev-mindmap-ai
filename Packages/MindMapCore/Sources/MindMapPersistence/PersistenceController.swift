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
            ModelConfiguration("MindMapAI", schema: schema, cloudKitDatabase: .none)
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
        ModelConfiguration("MindMapAI", schema: Schema(versionedSchema: SchemaV1.self), cloudKitDatabase: .none).url
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

import Foundation
import SwiftData

/// Opens the app's store.
public enum PersistenceController {
    public enum Location: Sendable {
        /// The app's default store on this device.
        case standard
        case file(URL)
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
        case .inMemory:
            ModelConfiguration("MindMapAI", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, migrationPlan: MindMapMigrationPlan.self, configurations: configuration)
    }

    public static func makeRepository(at location: Location = .standard) throws -> SwiftDataMapRepository {
        SwiftDataMapRepository(modelContainer: try makeContainer(at: location))
    }
}

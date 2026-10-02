import SwiftData

/// The schema the app opens. Records are always written through these names,
/// never through a shipped schema's types, except by test fixtures.
typealias CurrentSchema = SchemaV2
typealias MapRecord = CurrentSchema.MapRecord
typealias NodeRecord = CurrentSchema.NodeRecord
typealias EdgeRecord = CurrentSchema.EdgeRecord
typealias TagRecord = CurrentSchema.TagRecord
typealias NodeTagRecord = CurrentSchema.NodeTagRecord
typealias GroupRecord = CurrentSchema.GroupRecord

/// Every schema the app has shipped, oldest first. A new version adds a
/// schema, a stage here, and a test that opens the older stores with it.
enum MindMapMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }

    static var stages: [MigrationStage] {
        // V2 only adds optional properties and new records.
        [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)]
    }
}

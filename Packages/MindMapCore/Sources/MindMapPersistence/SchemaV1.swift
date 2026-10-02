import Foundation
import SwiftData

/// The first stored schema.
///
/// Rules that keep it ready for CloudKit sync: every property has a default or
/// is optional, there are no unique constraints, and records point at each
/// other by UUID instead of SwiftData relationships, so a node that syncs
/// before its parent is stored as-is and `GraphRepair` decides what to do.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [MapRecord.self, NodeRecord.self, EdgeRecord.self]
    }

    @Model
    final class MapRecord {
        var mapID: UUID = UUID()
        var title: String = ""
        var rootNodeID: UUID?
        var createdAt: Date = Date.distantPast
        var updatedAt: Date = Date.distantPast
        var isFavorite: Bool = false
        var themeRaw: String = "standard"
        var layoutStyleRaw: String = "horizontalTree"

        init(mapID: UUID) {
            self.mapID = mapID
        }
    }

    @Model
    final class NodeRecord {
        var nodeID: UUID = UUID()
        var mapID: UUID = UUID()
        var parentID: UUID?
        var title: String = ""
        var note: String?
        var sortOrder: Double = 0
        var isCollapsed: Bool = false
        var nodeTypeRaw: String = "topic"
        var originRaw: String = "user"
        var createdAt: Date = Date.distantPast
        var updatedAt: Date = Date.distantPast

        init(nodeID: UUID, mapID: UUID) {
            self.nodeID = nodeID
            self.mapID = mapID
        }
    }

    @Model
    final class EdgeRecord {
        var edgeID: UUID = UUID()
        var mapID: UUID = UUID()
        var sourceNodeID: UUID = UUID()
        var targetNodeID: UUID = UUID()
        var edgeTypeRaw: String = "relationship"
        var label: String?
        var createdAt: Date = Date.distantPast
        var updatedAt: Date = Date.distantPast

        init(edgeID: UUID, mapID: UUID) {
            self.edgeID = edgeID
            self.mapID = mapID
        }
    }
}

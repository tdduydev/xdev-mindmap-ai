import Foundation
import SwiftData

/// Recently Deleted (MM-19), node organization (MM-32 to MM-37) and the V1
/// node types (MM-59: link, floating topic, image, summary, callout) in one
/// schema change, so one migration stage and one CloudKit deployment. The
/// node types were added in place because no uploaded build had this schema
/// yet (docs/data-model.md, *V2 or V3*).
///
/// Additive only: V1's properties are unchanged, new properties are optional,
/// new records follow V1's CloudKit rules (defaults or optionals, no unique
/// constraints, UUIDs instead of relationships, raw strings with a fallback).
/// CloudKit's production schema never drops a field, so nothing here is for a
/// feature that is not built yet (docs/data-model.md, *Not in V2*).
enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [MapRecord.self, NodeRecord.self, EdgeRecord.self, TagRecord.self, NodeTagRecord.self, GroupRecord.self,
         ImageRecord.self]
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
        /// Set when the map goes to Recently Deleted.
        var deletedAt: Date?

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
        var colorToken: String?
        var symbol: String?
        var taskStateRaw: String?
        var priority: Int?
        /// Calendar days as `YYYY-MM-DD`, so they do not move with the time zone.
        var startDate: String?
        var dueDate: String?
        var linkURL: String?
        /// A floating topic's centre relative to the central topic's; both or neither.
        var positionX: Double?
        var positionY: Double?
        var calloutText: String?

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
        var lineStyleRaw: String?
        var arrowHeadsRaw: String?
        var colorToken: String?

        init(edgeID: UUID, mapID: UUID) {
            self.edgeID = edgeID
            self.mapID = mapID
        }
    }

    @Model
    final class TagRecord {
        var tagID: UUID = UUID()
        /// Nil for a shared tag, offered in every map.
        var mapID: UUID?
        var name: String = ""
        var colorToken: String?
        var symbol: String?
        var sortOrder: Double = 0
        var createdAt: Date = Date.distantPast
        var updatedAt: Date = Date.distantPast

        init(tagID: UUID, mapID: UUID?) {
            self.tagID = tagID
            self.mapID = mapID
        }
    }

    @Model
    final class NodeTagRecord {
        var linkID: UUID = UUID()
        /// The topic's map, also for a shared tag, so a map loads its links by `mapID`.
        var mapID: UUID = UUID()
        var nodeID: UUID = UUID()
        var tagID: UUID = UUID()
        var originRaw: String = "user"
        var createdAt: Date = Date.distantPast
        var updatedAt: Date = Date.distantPast

        init(linkID: UUID, mapID: UUID) {
            self.linkID = linkID
            self.mapID = mapID
        }
    }

    @Model
    final class GroupRecord {
        var groupID: UUID = UUID()
        var mapID: UUID = UUID()
        var kindRaw: String = "boundary"
        var parentNodeID: UUID?
        var firstNodeID: UUID?
        var lastNodeID: UUID?
        var title: String?
        var colorToken: String?
        var originRaw: String = "user"
        var createdAt: Date = Date.distantPast
        var updatedAt: Date = Date.distantPast
        /// For `kind = summary`: the summary topic.
        var summaryNodeID: UUID?

        init(groupID: UUID, mapID: UUID) {
            self.groupID = groupID
            self.mapID = mapID
        }
    }

    @Model
    final class ImageRecord {
        var imageID: UUID = UUID()
        var mapID: UUID = UUID()
        var nodeID: UUID = UUID()
        /// A file beside the store, not a column, and a `CKAsset` in iCloud,
        /// so a map's rows stay small.
        @Attribute(.externalStorage) var data: Data?
        var uniformType: String = "public.heic"
        var pixelWidth: Int = 0
        var pixelHeight: Int = 0
        var byteCount: Int = 0
        var displayWidth: Double?
        var altText: String?
        var createdAt: Date = Date.distantPast
        var updatedAt: Date = Date.distantPast

        init(imageID: UUID, mapID: UUID) {
            self.imageID = imageID
            self.mapID = mapID
        }
    }
}

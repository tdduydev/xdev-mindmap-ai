import Foundation
import SwiftData

/// The chat saved with each map (MM-55, docs/chat.md). SchemaV2 shipped to
/// TestFlight (builds 202610030024 and 202610030030), so the chat comes as a
/// new schema instead of a record added to V2.
///
/// Additive only: V2's records are copied unchanged, and `ChatTurnRecord`
/// follows the same CloudKit rules (defaults or optionals, no unique
/// constraints, the map by UUID instead of a relationship).
enum SchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [MapRecord.self, NodeRecord.self, EdgeRecord.self, TagRecord.self, NodeTagRecord.self, GroupRecord.self,
         ImageRecord.self, ChatTurnRecord.self]
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

    /// One question and answer of a map's chat (MM-55). One record per turn,
    /// not one per conversation, so two devices that ask at the same time
    /// each add a record instead of overwriting one, and a record stays small.
    @Model
    final class ChatTurnRecord {
        var turnID: UUID = UUID()
        var mapID: UUID = UUID()
        var question: String = ""
        /// As the model wrote it, handles in brackets included.
        var answer: String = ""
        /// `[ChatCitation]` as JSON: a turn cites a few topics, read only with the turn.
        var citationsData: Data?
        /// Orders the conversation; there is no sort order to keep in step across devices.
        var createdAt: Date = Date.distantPast

        init(turnID: UUID, mapID: UUID) {
            self.turnID = turnID
            self.mapID = mapID
        }
    }
}

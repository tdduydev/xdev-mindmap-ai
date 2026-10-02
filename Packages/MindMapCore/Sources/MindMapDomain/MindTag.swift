import Foundation

/// A label people put on topics. A tag belongs to one map, or to the library
/// when `mapID` is nil (a shared tag, offered in every map).
///
/// Names are not unique in storage: two devices can create the same tag
/// offline, and `GraphRepair` merges tags whose `key` is equal.
public struct MindTag: Identifiable, Hashable, Sendable, Codable {
    public let id: TagID
    /// Nil for a shared tag.
    public var mapID: MapID?
    public var name: String
    public var color: TopicColor?
    public var symbol: String?
    public var sortOrder: Double
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: TagID = TagID(),
        mapID: MapID?,
        name: String,
        color: TopicColor? = nil,
        symbol: String? = nil,
        sortOrder: Double = 0,
        createdAt: Date = .now,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.mapID = mapID
        self.name = name
        self.color = color
        self.symbol = symbol
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    public var isShared: Bool { mapID == nil }

    /// Two tags of one scope are the same tag when their keys are equal.
    public var key: String { Self.key(for: name) }

    public static let maximumNameLength = 40

    /// NFC, then case folded without a locale, every diacritic kept: "Việc" and
    /// "VIỆC" are one tag, "việc" and "viec" are two, and "đ" is not "d".
    /// Deliberately stricter than search folding: a tag is an identity.
    public static func key(for name: String) -> String {
        name.precomposedStringWithCanonicalMapping.folding(options: .caseInsensitive, locale: nil)
    }

    /// Trimmed, inner whitespace collapsed to one space, a leading `#` dropped.
    /// Nil when nothing is left or the name is longer than `maximumNameLength`.
    public static func normalizedName(_ text: String) -> String? {
        var name = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if name.hasPrefix("#") {
            name = String(name.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        guard !name.isEmpty, name.count <= maximumNameLength else { return nil }
        return name
    }
}

/// One tag on one topic. A record per pair, rather than a list of tag IDs on
/// the node, so two devices tagging the same topic both keep their tags.
public struct MindNodeTag: Identifiable, Hashable, Sendable, Codable {
    public let id: NodeTagID
    /// The topic's map, also for a shared tag.
    public let mapID: MapID
    public var nodeID: NodeID
    public var tagID: TagID
    public var origin: NodeOrigin
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: NodeTagID = NodeTagID(),
        mapID: MapID,
        nodeID: NodeID,
        tagID: TagID,
        origin: NodeOrigin = .user,
        createdAt: Date = .now,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.mapID = mapID
        self.nodeID = nodeID
        self.tagID = tagID
        self.origin = origin
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

import Foundation

/// A mind map document. Its nodes and edges are separate values, stored as
/// separate records, so one edit touches one record instead of the whole map.
public struct MindMap: Identifiable, Hashable, Sendable, Codable {
    public let id: MapID
    public var title: String
    public var rootNodeID: NodeID?
    public var createdAt: Date
    public var updatedAt: Date
    public var isFavorite: Bool
    public var theme: MindMapTheme
    public var layoutConfiguration: LayoutConfiguration

    public init(
        id: MapID = MapID(),
        title: String,
        rootNodeID: NodeID? = nil,
        createdAt: Date = .now,
        updatedAt: Date? = nil,
        isFavorite: Bool = false,
        theme: MindMapTheme = .standard,
        layoutConfiguration: LayoutConfiguration = LayoutConfiguration()
    ) {
        self.id = id
        self.title = title
        self.rootNodeID = rootNodeID
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.isFavorite = isFavorite
        self.theme = theme
        self.layoutConfiguration = layoutConfiguration
    }
}

/// The look of a map: which colours its branches take (FR-THM-02). Stored as
/// the raw string, so these values must never be renamed.
public enum MindMapTheme: String, Hashable, Sendable, Codable, CaseIterable {
    case standard
    case xdevBlue
    case graphite

    /// A theme this version does not know, written by a newer one, opens as
    /// Standard instead of failing to open the map (FR-THM-03).
    public init(storedValue: String) {
        self = MindMapTheme(rawValue: storedValue) ?? .standard
    }

    public init(from decoder: any Decoder) throws {
        self.init(storedValue: try decoder.singleValueContainer().decode(String.self))
    }
}

/// How a map arranges its nodes. This is the user's stored choice; spacing and
/// geometry belong to the layout engine.
public struct LayoutConfiguration: Hashable, Sendable, Codable {
    public var style: LayoutStyle

    public init(style: LayoutStyle = .horizontalTree) {
        self.style = style
    }
}

public enum LayoutStyle: String, Hashable, Sendable, Codable, CaseIterable {
    /// Central topic in the middle, branches extending sideways (`HorizontalTreeLayout`).
    case horizontalTree
}

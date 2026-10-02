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

/// The look of a map. V1 has one; the type exists so stored maps already carry the choice.
public enum MindMapTheme: String, Hashable, Sendable, Codable, CaseIterable {
    case standard
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

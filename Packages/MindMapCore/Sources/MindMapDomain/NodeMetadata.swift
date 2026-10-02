import Foundation

/// Facts about a node that are not its content.
public struct NodeMetadata: Hashable, Sendable, Codable {
    public var origin: NodeOrigin

    public init(origin: NodeOrigin = .user) {
        self.origin = origin
    }
}

/// Where a node came from. Kept after an AI suggestion is accepted, so the map
/// can still tell the user which content the model wrote.
public enum NodeOrigin: String, Hashable, Sendable, Codable, CaseIterable {
    case user
    case ai
    case imported
}

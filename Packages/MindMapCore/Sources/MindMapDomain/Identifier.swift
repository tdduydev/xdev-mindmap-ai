import Foundation

/// A UUID tagged with the type it identifies, so a node ID cannot be passed
/// where a map or edge ID is expected.
public struct Identifier<Owner>: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue.uuidString }
}

extension Identifier: Codable {
    // Encoded as a bare UUID so stored and exported data does not depend on the Swift type.
    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension Identifier: Comparable {
    /// An arbitrary but stable order, used only to break ties deterministically
    /// so every device sorts the same data the same way.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue.uuidString < rhs.rawValue.uuidString
    }
}

public typealias MapID = Identifier<MindMap>
public typealias NodeID = Identifier<MindNode>
public typealias EdgeID = Identifier<MindEdge>
public typealias TagID = Identifier<MindTag>
public typealias NodeTagID = Identifier<MindNodeTag>
public typealias GroupID = Identifier<MindGroup>

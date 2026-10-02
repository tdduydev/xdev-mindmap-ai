import Foundation
import MindMapDomain
import MindMapGraph
import MindMapPersistence

/// One topic in one map: what an MCP client or a chat citation points at.
public struct TopicRef: Hashable, Sendable, Codable {
    public var mapID: MapID
    public var nodeID: NodeID

    public init(mapID: MapID, nodeID: NodeID) {
        self.mapID = mapID
        self.nodeID = nodeID
    }
}

/// Where queries read a map's graph. The app answers from the editor's live
/// state for maps that are open, so an AI app or the chat sees what the window
/// shows rather than the last save, and from the store for the rest.
public protocol GraphSource: Sendable {
    /// Nil when the map does not exist. May return a map in Recently Deleted;
    /// `MapQueries` leaves those out itself.
    func graph(for mapID: MapID) async throws -> GraphState?

    /// Maps whose live graph may be ahead of the store. Library search reads
    /// these graphs directly instead of trusting the store's text index.
    func openMapIDs() async -> Set<MapID>
}

extension GraphSource {
    public func openMapIDs() async -> Set<MapID> { [] }
}

/// Reads only the store: for tests, and for any caller with no open maps.
public struct RepositoryGraphSource: GraphSource {
    private let repository: any MapRepository

    public init(repository: any MapRepository) {
        self.repository = repository
    }

    public func graph(for mapID: MapID) async throws -> GraphState? {
        try await repository.loadGraph(for: mapID)
    }
}

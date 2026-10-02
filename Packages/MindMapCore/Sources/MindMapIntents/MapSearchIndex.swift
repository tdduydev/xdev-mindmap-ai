import CoreSpotlight
import Foundation
import MindMapDomain
import OSLog

/// Where map titles are indexed for system search (FR-SYS-04). A protocol so
/// the library and the intents can be tested without touching Spotlight.
public protocol MapSearchIndex: Sendable {
    /// Makes the index hold exactly `maps`: maps deleted while the app was
    /// away, or on another device, drop out.
    func replaceAll(with maps: [MindMap]) async
    /// A new map, or a new title.
    func update(_ map: MindMap) async
    func remove(_ mapID: MapID) async
}

/// Indexes `MapEntity` values, so a Spotlight result is the same entity
/// Shortcuts sees, and opening it runs `OpenMapIntent`.
///
/// Only titles are indexed, never topics or notes: the index lives on this
/// device, but titles are all FR-SYS-04 asks for.
public struct SpotlightMapIndex: MapSearchIndex {
    private static let log = Logger(subsystem: "asia.xdev.mindmapai", category: "Spotlight")

    public init() {}

    public func replaceAll(with maps: [MindMap]) async {
        do {
            try await CSSearchableIndex.default().deleteAppEntities(ofType: MapEntity.self)
            try await CSSearchableIndex.default().indexAppEntities(maps.map(MapEntity.init))
        } catch {
            Self.log.error("Reindexing maps failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func update(_ map: MindMap) async {
        do {
            try await CSSearchableIndex.default().indexAppEntities([MapEntity(map)])
        } catch {
            Self.log.error("Indexing a map failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func remove(_ mapID: MapID) async {
        do {
            try await CSSearchableIndex.default().deleteAppEntities(identifiedBy: [mapID.rawValue], ofType: MapEntity.self)
        } catch {
            Self.log.error("Removing a map from the index failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

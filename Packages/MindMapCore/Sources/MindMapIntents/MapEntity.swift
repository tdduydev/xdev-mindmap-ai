import AppIntents
import CoreSpotlight
import Foundation
import MindMapDomain

/// A map as Shortcuts, Siri and Spotlight see it: its ID and title only.
public struct MapEntity: AppEntity, IndexedEntity {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Map"
    public static let defaultQuery = MapEntityQuery()

    /// A bare UUID: App Intents stores entity IDs, and `MapID` encodes as one.
    public let id: UUID
    public let title: String
    public let updatedAt: Date

    public init(_ map: MindMap) {
        id = map.id.rawValue
        title = map.title
        updatedAt = map.updatedAt
    }

    public var mapID: MapID { MapID(id) }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }

    public var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.title = title
        attributes.contentModificationDate = updatedAt
        return attributes
    }
}

public struct MapEntityQuery: EntityStringQuery {
    @Dependency private var services: MindMapIntentServices

    public init() {}

    public func entities(for identifiers: [UUID]) async throws -> [MapEntity] {
        try await services.maps(withIDs: identifiers.map(MapID.init)).map(MapEntity.init)
    }

    public func entities(matching string: String) async throws -> [MapEntity] {
        try await services.maps(matching: string).map(MapEntity.init)
    }

    public func suggestedEntities() async throws -> [MapEntity] {
        try await services.recentMaps().map(MapEntity.init)
    }
}

import AppIntents
import Foundation
import MindMapDomain

/// The intents this package declares. The app includes it from its own
/// `AppIntentsPackage`, which is how the system finds intents in a package.
public struct MindMapIntentsPackage: AppIntentsPackage {}

// Titles and descriptions are looked up in the app's string catalog at run
// time, where they are kept with en and vi like every other UI string.

public struct NewMapIntent: AppIntent {
    public static let title: LocalizedStringResource = "New Mind Map"
    public static let description = IntentDescription("Creates an empty map and opens it.")
    public static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Title")
    public var mapTitle: String?

    @Dependency private var services: MindMapIntentServices

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<MapEntity> {
        .result(value: MapEntity(try await services.newMap(title: mapTitle)))
    }
}

public struct MapFromClipboardIntent: AppIntent {
    public static let title: LocalizedStringResource = "Map from Clipboard"
    public static let description = IntentDescription("Makes a map from the text on the clipboard: each line or Markdown list item becomes a topic.")
    // In the foreground: iOS lets the app read the clipboard only there.
    public static let supportedModes: IntentModes = .foreground

    @Dependency private var services: MindMapIntentServices

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<MapEntity> {
        .result(value: MapEntity(try await services.mapFromClipboard()))
    }
}

public struct AddIdeaIntent: AppIntent {
    public static let title: LocalizedStringResource = "Add Idea"
    public static let description = IntentDescription("Adds a topic under the central topic of a map. Without a map, the idea goes to the most recently edited one.")
    public static let supportedModes: IntentModes = .background

    @Parameter(title: "Idea", inputOptions: String.IntentInputOptions(multiline: false))
    public var idea: String

    @Parameter(title: "Map")
    public var map: MapEntity?

    @Dependency private var services: MindMapIntentServices

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<MapEntity> & ProvidesDialog {
        let updated = try await services.addIdea(idea, to: map?.mapID)
        return .result(value: MapEntity(updated), dialog: "Added to \(updated.title).")
    }
}

public struct OpenRecentMapIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Recent Map"
    public static let description = IntentDescription("Opens the most recently edited map.")
    public static let supportedModes: IntentModes = .foreground

    @Dependency private var services: MindMapIntentServices

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<MapEntity> {
        .result(value: MapEntity(try await services.openRecent()))
    }
}

/// Opens a chosen map. Spotlight runs it when someone picks an indexed map.
public struct OpenMapIntent: OpenIntent {
    public static let title: LocalizedStringResource = "Open Map"
    public static let description = IntentDescription("Opens a map.")
    public static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Map")
    public var target: MapEntity

    @Dependency private var services: MindMapIntentServices

    public init() {}

    public init(target: MapEntity) {
        self.target = target
    }

    public func perform() async throws -> some IntentResult {
        try await services.open(target.mapID)
        return .result()
    }
}

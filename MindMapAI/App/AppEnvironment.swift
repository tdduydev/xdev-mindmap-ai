import Foundation
import MindMapIntents
import MindMapPersistence
import OSLog

/// The app's long-lived services, built once at launch. Only the store opens
/// here; AI, importers and exporters are created by the features that use them,
/// when first used, so launch stays fast.
final class AppEnvironment {
    let repository: any MapRepository
    let spotlightIndex: any MapSearchIndex
    /// Maps the intents asked to open; every window watches it.
    let openRequests: MapOpenRequests
    /// One session per open map, whatever the number of windows showing it.
    let openMaps: OpenMaps
    /// Writes the UI test fixture; nil outside the UI test mode.
    private let seeding: Task<Void, Never>?

    init(
        repository: any MapRepository,
        spotlightIndex: any MapSearchIndex = SpotlightMapIndex(),
        openRequests: MapOpenRequests = MapOpenRequests(),
        seeding: Task<Void, Never>? = nil
    ) {
        self.repository = repository
        self.spotlightIndex = spotlightIndex
        self.openRequests = openRequests
        openMaps = OpenMaps(repository: repository)
        self.seeding = seeding
    }

    /// `sync` is how the store mirrors to iCloud (`CloudSyncMonitor.storeSync`).
    static func live(sync: PersistenceController.Sync) -> AppLaunch {
        do {
            if let mode = UITestMode.current {
                return .ready(try uiTest(mode))
            }
            #if DEBUG
            initializeCloudKitSchemaIfAsked(sync: sync)
            #endif
            return .ready(AppEnvironment(repository: try PersistenceController.makeRepository(at: storeLocation, sync: sync)))
        } catch {
            Log.persistence.fault("The store did not open: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    #if DEBUG
    /// `-InitializeCloudKitSchema` on a development build signed for the
    /// container creates every record type in CloudKit's development
    /// environment, to deploy to production from the CloudKit Console
    /// (cloudkit-sync.md, *Schema*; FR-SYN-07).
    private static func initializeCloudKitSchemaIfAsked(sync: PersistenceController.Sync) {
        guard ProcessInfo.processInfo.arguments.contains("-InitializeCloudKitSchema"),
              case .privateDatabase(let identifier) = sync else { return }
        do {
            try PersistenceController.initializeCloudKitSchema(containerIdentifier: identifier)
            Log.persistence.notice("CloudKit development schema initialized")
        } catch {
            Log.persistence.error("Initializing the CloudKit schema failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    #endif

    /// The App Group store, shared with the Share Extension. Without the
    /// entitlement (an unsigned local build) the app keeps its own store, so it
    /// still runs; only sharing into it is unavailable.
    private static var storeLocation: PersistenceController.Location {
        guard let containerURL = AppGroupAccess.containerURL else {
            Log.persistence.error("No App Group container; using the app's own store")
            return .standard
        }
        return .appGroup(containerURL: containerURL)
    }

    /// What the App Intents run against (FR-SYS-03).
    func intentServices() -> MindMapIntentServices {
        let openRequests = openRequests
        return MindMapIntentServices(
            repository: repository,
            index: spotlightIndex,
            untitledTitle: { String(localized: "Untitled Map") },
            openMap: { openRequests.open($0) },
            readClipboard: { Clipboard.string }
        )
    }

    /// Waits until the store holds what the library should show first.
    func prepare() async {
        await seeding?.value
    }

    /// An in-memory store, so UI tests never see or touch the person's maps,
    /// and no Spotlight index, so fixture maps never show in the Mac's search.
    private static func uiTest(_ mode: UITestMode) throws -> AppEnvironment {
        let repository = try PersistenceController.makeRepository(at: .inMemory)
        let maps = try mode.fixture.makeMaps()
        let seeding = Task {
            do {
                for graph in maps.graphs {
                    try await repository.create(graph)
                }
                for id in maps.favorites {
                    try await repository.setFavorite(true, for: id)
                }
            } catch {
                Log.persistence.fault("The UI test fixture was not saved: \(error.localizedDescription, privacy: .public)")
            }
        }
        return AppEnvironment(repository: repository, spotlightIndex: NoSearchIndex(), seeding: seeding)
    }
}

enum AppLaunch {
    case ready(AppEnvironment)
    /// The store could not open; the app shows a recovery screen instead of crashing.
    case failed
}

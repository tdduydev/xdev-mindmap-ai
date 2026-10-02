import Foundation
import MindMapIntents
import MindMapPersistence
import OSLog

/// The app's long-lived services, built once at launch. Only the store opens
/// here; AI, importers and exporters are created by the features that use them,
/// when first used, so launch stays fast.
final class AppEnvironment {
    let repository: any MapRepository
    let searchIndex: any MapSearchIndex
    /// Maps the intents asked to open; every window watches it.
    let openRequests: MapOpenRequests

    init(
        repository: any MapRepository,
        searchIndex: any MapSearchIndex = SpotlightMapIndex(),
        openRequests: MapOpenRequests = MapOpenRequests()
    ) {
        self.repository = repository
        self.searchIndex = searchIndex
        self.openRequests = openRequests
    }

    static func live() -> AppLaunch {
        do {
            return .ready(AppEnvironment(repository: try PersistenceController.makeRepository(at: storeLocation)))
        } catch {
            Log.persistence.fault("The store did not open: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

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
            index: searchIndex,
            untitledTitle: { String(localized: "Untitled Map") },
            openMap: { openRequests.open($0) },
            readClipboard: { Clipboard.string }
        )
    }
}

enum AppLaunch {
    case ready(AppEnvironment)
    /// The store could not open; the app shows a recovery screen instead of crashing.
    case failed
}

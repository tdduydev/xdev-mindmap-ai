import MindMapPersistence
import OSLog

/// The app's long-lived services, built once at launch. Only the store opens
/// here; AI, importers and exporters are created by the features that use them,
/// when first used, so launch stays fast.
final class AppEnvironment {
    let repository: any MapRepository

    init(repository: any MapRepository) {
        self.repository = repository
    }

    static func live() -> AppLaunch {
        do {
            return .ready(AppEnvironment(repository: try PersistenceController.makeRepository()))
        } catch {
            Log.persistence.fault("The store did not open: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }
}

enum AppLaunch {
    case ready(AppEnvironment)
    /// The store could not open; the app shows a recovery screen instead of crashing.
    case failed
}

import MindMapPersistence
import OSLog

/// The app's long-lived services, built once at launch. Only the store opens
/// here; AI, importers and exporters are created by the features that use them,
/// when first used, so launch stays fast.
final class AppEnvironment {
    let repository: any MapRepository
    /// Writes the UI test fixture; nil outside the UI test mode.
    private let seeding: Task<Void, Never>?

    init(repository: any MapRepository, seeding: Task<Void, Never>? = nil) {
        self.repository = repository
        self.seeding = seeding
    }

    static func live() -> AppLaunch {
        do {
            if let mode = UITestMode.current {
                return .ready(try uiTest(mode))
            }
            return .ready(AppEnvironment(repository: try PersistenceController.makeRepository()))
        } catch {
            Log.persistence.fault("The store did not open: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    /// Waits until the store holds what the library should show first.
    func prepare() async {
        await seeding?.value
    }

    /// An in-memory store, so UI tests never see or touch the person's maps.
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
        return AppEnvironment(repository: repository, seeding: seeding)
    }
}

enum AppLaunch {
    case ready(AppEnvironment)
    /// The store could not open; the app shows a recovery screen instead of crashing.
    case failed
}

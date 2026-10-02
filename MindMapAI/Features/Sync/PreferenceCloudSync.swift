import Foundation

/// Mirrors only taste preferences through the person's iCloud key-value store.
/// Map content stays in SwiftData/CloudKit, and device controls stay local.
final class PreferenceCloudSync {
    static let keys: [String] = [
        NewMapPreferences.themeKey,
        ExportPreferences.includeNotesKey, ExportPreferences.imageScaleKey,
        ExportPreferences.pageModeKey, ExportPreferences.paperKey,
        ExportPreferences.backgroundKey
    ]

    private let defaults: UserDefaults
    private let cloud: NSUbiquitousKeyValueStore
    private let isEnabled: Bool
    private var observers: [any NSObjectProtocol] = []

    init(
        isEnabled: Bool,
        defaults: UserDefaults = AppDefaults.store,
        cloud: NSUbiquitousKeyValueStore = .default
    ) {
        self.isEnabled = isEnabled
        self.defaults = defaults
        self.cloud = cloud
    }

    func start() {
        guard isEnabled, observers.isEmpty else { return }
        cloud.synchronize()
        // Take cloud values first, so reopening one device cannot overwrite a
        // choice changed on another device while this app was closed.
        for key in Self.keys {
            if let remote = cloud.object(forKey: key) {
                defaults.set(remote, forKey: key)
            } else if let local = defaults.object(forKey: key) {
                cloud.set(local, forKey: key)
            }
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pushLocalChanges() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main
        ) { [weak self] note in
            let changed = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            MainActor.assumeIsolated { self?.takeRemoteChanges(changed) }
        })
    }

    private func pushLocalChanges() {
        for key in Self.keys {
            let local = defaults.object(forKey: key)
            let remote = cloud.object(forKey: key)
            guard !Self.equal(local, remote) else { continue }
            if let local { cloud.set(local, forKey: key) }
            else { cloud.removeObject(forKey: key) }
        }
    }

    private func takeRemoteChanges(_ changed: [String]) {
        for key in changed where Self.keys.contains(key) {
            let remote = cloud.object(forKey: key)
            guard !Self.equal(defaults.object(forKey: key), remote) else { continue }
            if let remote { defaults.set(remote, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
    }

    private static func equal(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (lhs as NSObject, rhs as NSObject): lhs == rhs
        default: false
        }
    }
}

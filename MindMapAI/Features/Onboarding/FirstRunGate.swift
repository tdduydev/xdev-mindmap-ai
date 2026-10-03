import Foundation
import MindMapPersistence

/// "This person has had the first run" as the iCloud key-value store sees it,
/// so a second device or a reinstall skips the sample map (FR-ONB-01, FR-SYN-08).
protocol FirstRunCloudFlag {
    var isSet: Bool { get }
    func set()
}

/// The flag in the person's iCloud key-value store, beside the preferences of
/// `PreferenceCloudSync`. Its own key space, so the local key name is reused.
struct UbiquitousFirstRunFlag: FirstRunCloudFlag {
    static let key = "onboarding.completed"
    var store: NSUbiquitousKeyValueStore = .default

    var isSet: Bool { store.bool(forKey: Self.key) }

    func set() {
        guard !isSet else { return }
        store.set(true, forKey: Self.key)
    }
}

/// Decides whether an empty library is a first run that gets the sample map.
/// With iCloud on, a store that looks empty may only be waiting for CloudKit:
/// creating the sample then would sync it up and add one per device.
struct FirstRunGate {
    enum Decision: Equatable {
        /// The person has maps, here or in iCloud: no sample, no introduction.
        case skip
        case createSample
    }

    /// Whether the store mirrors to iCloud this launch (`CloudSyncMonitor.storeSync`).
    var isCloudStoreOn: Bool
    var cloudFlag: any FirstRunCloudFlag
    var accountStatus: @MainActor () async -> CloudAccount
    /// Returns once the first CloudKit import of this launch finished, the
    /// cloud flag arrived, or the time is up, whichever comes first.
    var waitForFirstImport: @MainActor (_ flag: any FirstRunCloudFlag) async -> Void
    /// Reloads and says whether the library or Recently Deleted holds a map.
    var libraryHasMaps: @MainActor () async -> Bool

    func decide() async -> Decision {
        if await libraryHasMaps() {
            recordCompleted()
            return .skip
        }
        guard isCloudStoreOn else { return .createSample }
        if cloudFlag.isSet { return .skip }
        // Signed out or restricted, nothing can arrive from iCloud: the
        // empty store is the whole library, as with sync off.
        guard await accountStatus() == .available else { return .createSample }
        await waitForFirstImport(cloudFlag)
        if cloudFlag.isSet { return .skip }
        if await libraryHasMaps() {
            recordCompleted()
            return .skip
        }
        return .createSample
    }

    /// Tells the person's other devices. Only with the store in iCloud: a
    /// device keeping its maps local must not stop another one's sample.
    func recordCompleted() {
        guard isCloudStoreOn else { return }
        cloudFlag.set()
    }
}

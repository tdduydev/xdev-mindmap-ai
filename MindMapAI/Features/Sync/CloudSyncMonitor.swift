import CloudKit
import CoreData
import Foundation
import MindMapPersistence
import Network
import Observation
import OSLog

/// Whether the store mirrors to iCloud, and how that is going (FR-SYN-01..03,
/// FR-SET-04). Reads the account, the network and the mirroring's own events;
/// never blocks editing and never shows an alert.
@Observable
final class CloudSyncMonitor {
    /// The device's choice (FR-SYN-06), on unless turned off.
    static let enabledKey = "sync.iCloudEnabled"

    /// Built with the iCloud entitlement (`MINDMAP_ICLOUD = YES`). Without it,
    /// asking CloudKit for the container would stop the app, so nothing here
    /// touches CloudKit.
    static var isBuildEntitled: Bool {
        #if MINDMAP_ICLOUD
        true
        #else
        false
        #endif
    }

    /// How the store opened at launch. Turning sync on or off applies at the
    /// next launch: reopening the store under open windows is not worth the risk.
    let storeSync: PersistenceController.Sync
    private(set) var account: CloudAccount = .unknown
    private(set) var isNetworkReachable = true
    private(set) var activity = CloudSyncActivity()

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    /// Settings writes the switch through `@AppStorage`; this follows it.
    private(set) var isEnabled: Bool

    init(defaults: UserDefaults = AppDefaults.store, isEntitled: Bool = isBuildEntitled, isUITest: Bool = UITestMode.isActive) {
        self.defaults = defaults
        let enabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        isEnabled = enabled
        // UI tests run on a throwaway in-memory store that must never reach iCloud.
        storeSync = isEntitled && enabled && !isUITest ? .appContainer : .off
    }

    var state: CloudSyncState {
        CloudSyncState(
            isEnabled: storeSync != .off,
            isAvailable: Self.isBuildEntitled,
            account: account,
            isNetworkReachable: isNetworkReachable,
            activity: activity
        )
    }

    /// The switch says something other than what the store does now.
    var needsRelaunch: Bool {
        Self.isBuildEntitled && isEnabled != (storeSync != .off)
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.enabledKey)
        isEnabled = enabled
    }

    // MARK: Observing

    /// Starts once, at launch; the observers live as long as the app.
    func start() {
        guard observers.isEmpty, storeSync != .off else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event
            guard let event else { return }
            let id = event.identifier
            let finished = event.endDate != nil
            let failed = finished && !event.succeeded
            let code = (event.error as? CKError)?.code
            let partialCodes = (event.error as? CKError)?.partialErrorsByItemID
                .map { $0.values.compactMap { ($0 as? CKError)?.code } } ?? []
            MainActor.assumeIsolated {
                let failure = failed ? Self.failure(code: code, partialCodes: partialCodes) : nil
                self?.activity.record(id, finished: finished, failure: failure)
            }
        })
        observers.append(center.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccount() }
        })
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let reachable = path.status == .satisfied
            Task { @MainActor in self?.isNetworkReachable = reachable }
        }
        monitor.start(queue: DispatchQueue(label: "asia.xdev.mindmapai.sync.network"))
        pathMonitor = monitor
        refreshAccount()
    }

    /// Also when the app comes back: the person may have signed in meanwhile.
    func refreshAccount() {
        guard case .privateDatabase(let identifier) = storeSync else { return }
        Task {
            do {
                let status = try await CKContainer(identifier: identifier).accountStatus()
                account = Self.account(for: status)
            } catch {
                Log.persistence.error("Reading the iCloud account failed: \(error.localizedDescription, privacy: .public)")
                account = .unknown
            }
        }
    }

    static func account(for status: CKAccountStatus) -> CloudAccount {
        switch status {
        case .available: .available
        case .noAccount: .noAccount
        case .restricted: .restricted
        case .temporarilyUnavailable: .temporarilyUnavailable
        case .couldNotDetermine: .unknown
        @unknown default: .unknown
        }
    }

    /// Only the code is logged: CloudKit errors can name records, and map
    /// content never goes to the log ([[privacy]]).
    static func failure(code: CKError.Code?, partialCodes: [CKError.Code] = []) -> CloudSyncFailure {
        guard let code else { return .other }
        Log.persistence.error("A sync step failed with CloudKit error \(code.rawValue, privacy: .public)")
        switch code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return .network
        case .quotaExceeded:
            return .quotaExceeded
        case .notAuthenticated, .accountTemporarilyUnavailable:
            return .notAuthenticated
        case .partialFailure where partialCodes.contains(.quotaExceeded):
            return .quotaExceeded
        default:
            return .other
        }
    }
}

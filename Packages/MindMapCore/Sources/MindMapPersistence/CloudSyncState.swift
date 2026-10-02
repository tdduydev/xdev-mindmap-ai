import Foundation

/// The app's CloudKit container. Created on the Apple Developer account and
/// named in the iCloud entitlement of the app (not of the Share Extension).
public enum CloudSyncContainer {
    public static let identifier = "iCloud.asia.xdev.mindmapai"
}

/// The person's iCloud account as CloudKit reports it, without CloudKit's
/// types, so the rules below can be tested anywhere.
public enum CloudAccount: Hashable, Sendable {
    /// Not asked yet, or CloudKit could not tell.
    case unknown
    case available
    case noAccount
    /// Parental controls or device management keep the app out of iCloud.
    case restricted
    /// Signed in, but iCloud needs the person first (new terms, a password).
    case temporarilyUnavailable
}

/// Why a sync step failed, as far as the person needs to know.
public enum CloudSyncFailure: Hashable, Sendable {
    /// No network, or iCloud could not be reached. Not an error: the step
    /// runs again once the device is back online (FR-SYN-03).
    case network
    /// The person's iCloud storage is full.
    case quotaExceeded
    /// The account went away or changed while syncing.
    case notAuthenticated
    case other
}

/// What the mirroring is doing, from the events of the store's CloudKit
/// mirroring (setup, import, export), each with an ID.
public struct CloudSyncActivity: Hashable, Sendable {
    private var running: Set<UUID> = []
    /// How the last finished step ended; nil once one succeeds.
    public private(set) var lastFailure: CloudSyncFailure?

    public init() {}

    public var isRunning: Bool { !running.isEmpty }

    /// A step started, or finished (`finished`), with `failure` if it failed.
    /// The same step reports start and end with one ID.
    public mutating func record(_ id: UUID, finished: Bool, failure: CloudSyncFailure? = nil) {
        guard finished else {
            running.insert(id)
            return
        }
        running.remove(id)
        lastFailure = failure
    }
}

/// What Settings and the status line say about sync (FR-SYN-03). Quiet by
/// design: only `error` asks for something, and never in an alert.
public enum CloudSyncState: Hashable, Sendable {
    /// Turned off in the app (FR-SYN-06).
    case off
    /// This build cannot use iCloud: it is not signed for the container.
    case unavailable
    case notSignedIn
    case restricted
    /// Signed in, but the account needs the person in System Settings.
    case accountNeedsAttention
    case waitingForNetwork
    case syncing
    case upToDate
    case error(CloudSyncFailure)

    /// Sync is on and changes are flowing, or will once back online.
    public var isActive: Bool {
        switch self {
        case .waitingForNetwork, .syncing, .upToDate: true
        case .error(let failure): failure != .notAuthenticated
        case .off, .unavailable, .notSignedIn, .restricted, .accountNeedsAttention: false
        }
    }

    /// Whether the status line shows at all: only while something is
    /// happening or something needs the person; up to date, off, or a build
    /// without iCloud say nothing (FR-SYN-03).
    public var isWorthShowing: Bool {
        switch self {
        case .syncing, .waitingForNetwork, .error: true
        case .off, .unavailable, .notSignedIn, .restricted, .accountNeedsAttention, .upToDate: false
        }
    }

    public init(
        isEnabled: Bool,
        isAvailable: Bool,
        account: CloudAccount,
        isNetworkReachable: Bool,
        activity: CloudSyncActivity
    ) {
        guard isAvailable else { self = .unavailable; return }
        guard isEnabled else { self = .off; return }
        switch account {
        case .noAccount: self = .notSignedIn; return
        case .restricted: self = .restricted; return
        case .temporarilyUnavailable: self = .accountNeedsAttention; return
        case .available, .unknown: break
        }
        guard isNetworkReachable else { self = .waitingForNetwork; return }
        if activity.isRunning {
            self = .syncing
        } else {
            switch activity.lastFailure {
            case nil: self = .upToDate
            case .network: self = .waitingForNetwork
            case .notAuthenticated: self = .notSignedIn
            case let failure?: self = .error(failure)
            }
        }
    }
}

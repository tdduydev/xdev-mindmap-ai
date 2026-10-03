import Foundation
import MindMapDomain
import MindMapSharing
import Observation
import OSLog
import WatchKit

/// What the watch shows and does: capture into the Inbox (FR-WCH-01), recent
/// maps (FR-WCH-02) and whether iCloud is on (FR-WCH-04).
@Observable
final class WatchModel {
    enum CaptureResult: Equatable {
        case added
        case failed
    }

    /// Nil when the store did not open; the screens say so instead of saving.
    private let inbox: InboxCapture?
    /// Signed for the CloudKit container. Without it nothing ever syncs.
    private let isCloudBuild: Bool

    private(set) var recentMaps: [MindMap] = []
    private(set) var isLoaded = false
    var isCapturing = false

    private static let logger = Logger(subsystem: "asia.xdev.mindmapai.watchkitapp", category: "capture")

    init(inbox: InboxCapture?, isCloudBuild: Bool) {
        self.inbox = inbox
        self.isCloudBuild = isCloudBuild
    }

    var isStoreAvailable: Bool { inbox != nil }

    /// No iCloud account on the watch, or a build without iCloud: maps from
    /// other devices cannot arrive, and captured ideas stay here until it is on.
    var isICloudOff: Bool {
        !isCloudBuild || FileManager.default.ubiquityIdentityToken == nil
    }

    func load() async {
        defer { isLoaded = true }
        guard let inbox else { return }
        do {
            recentMaps = try await inbox.recentMaps(limit: WatchLimits.recentMaps)
        } catch {
            Self.logger.error("Recent maps did not load: \(error.localizedDescription, privacy: .private)")
        }
    }

    func outline(of mapID: MapID) async -> [ReadOnlyTopic]? {
        guard let inbox else { return nil }
        return try? await inbox.outline(of: mapID)
    }

    /// Saves the idea on the watch at once, so it survives being offline; the
    /// store mirrors it to iCloud when it can.
    func addIdea(_ idea: String) async -> CaptureResult {
        guard let inbox else { return .failed }
        let title = String(localized: "Inbox", comment: "Title of the map that collects ideas captured on the watch.")
        // The wrist may drop right after Done; ask for a little time so the
        // save finishes before the app is suspended.
        let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "Saving an idea")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        do {
            try await inbox.addIdea(idea, inboxTitle: title)
            WKInterfaceDevice.current().play(.success)
            await load()
            return .added
        } catch {
            Self.logger.error("The idea was not saved: \(error.localizedDescription, privacy: .private)")
            WKInterfaceDevice.current().play(.failure)
            return .failed
        }
    }
}

enum WatchLimits {
    /// FR-WCH-02 [Đề xuất]: enough to find a recent map without scrolling long.
    static let recentMaps = 20
}

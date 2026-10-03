import MindMapPersistence
import MindMapSharing
import OSLog
import SwiftUI

@main
struct MindMapWatchApp: App {
    @State private var model = WatchModel.launch()

    var body: some Scene {
        WindowGroup {
            WatchRootView(model: model)
                .onOpenURL { url in
                    if WatchLink.isCapture(url) { model.isCapturing = true }
                }
        }
    }
}

/// Links the complication opens. The widget extension has its own copy of
/// the URL, because the two targets share no source.
enum WatchLink {
    static let capture = URL(string: "mindmapai-watch://capture")!

    static func isCapture(_ url: URL) -> Bool {
        url.scheme == capture.scheme && url.host() == capture.host()
    }
}

extension WatchModel {
    private static let logger = Logger(subsystem: "asia.xdev.mindmapai.watchkitapp", category: "store")

    /// The same store and schema as the phone, mirrored to the same private
    /// CloudKit container (ADR 0012). A build not signed for iCloud keeps the
    /// store on the watch, so capture still works in the Simulator.
    static func launch() -> WatchModel {
        #if MINDMAP_ICLOUD
        let sync = PersistenceController.Sync.appContainer
        let isCloudBuild = true
        #else
        let sync = PersistenceController.Sync.off
        let isCloudBuild = false
        #endif
        do {
            // UI tests start from an empty store that dies with the process.
            let repository = ProcessInfo.processInfo.arguments.contains("-uiTestInMemoryStore")
                ? try PersistenceController.makeRepository(at: .inMemory)
                : try PersistenceController.makeRepository(at: .standard, sync: sync)
            return WatchModel(
                inbox: InboxCapture(repository: repository, store: UbiquitousInboxStore()),
                isCloudBuild: isCloudBuild
            )
        } catch {
            logger.error("The store did not open: \(error.localizedDescription, privacy: .private)")
            return WatchModel(inbox: nil, isCloudBuild: isCloudBuild)
        }
    }
}

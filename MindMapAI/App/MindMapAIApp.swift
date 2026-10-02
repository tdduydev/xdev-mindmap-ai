import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct MindMapAIApp: App {
    static let mainWindowID = "main"

    @State private var launch = AppEnvironment.live()
    @State private var pro = ProEntitlement()
    @AppStorage(AppearancePreference.storageKey) private var appearance = AppearancePreference.system
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup(id: Self.mainWindowID) {
            Group {
                switch launch {
                case .ready(let environment):
                    RootView(environment: environment)
                case .failed:
                    StartupFailureView()
                }
            }
            .preferredColorScheme(appearance.colorScheme)
            .environment(pro)
            .task { await pro.start() }
            #if os(macOS)
            // A Mac window can stay in the active phase while another app is
            // in front, so coming back is caught from the app itself too.
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                Task { await pro.refresh() }
            }
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 760)
        #endif
        .commands { MapCommands() }
        // A refund or a purchase on another device can change while the app is in the background.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await pro.refresh() } }
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .preferredColorScheme(appearance.colorScheme)
                .environment(pro)
        }
        #endif
    }
}

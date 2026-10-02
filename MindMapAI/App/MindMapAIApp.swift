import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct MindMapAIApp: App {
    static let mainWindowID = "main"

    @State private var launch = AppEnvironment.live()
    @State private var pro: ProEntitlement
    /// Shared by every window and Settings; the model itself loads on first use.
    @State private var ai: AIService
    @AppStorage(AppearancePreference.storageKey) private var appearance = AppearancePreference.system
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let pro = ProEntitlement()
        _pro = State(initialValue: pro)
        // The AI's Pro features ask the same entitlement as every other Pro feature.
        _ai = State(initialValue: AIService(entitlements: pro))
        // Before any view resolves a brand font by name.
        BrandFont.registerAll()
    }

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
            .environment(ai)
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
        .commands {
            MapCommands(ai: ai)
            // Show/Hide Inspector (⌃⌘I) in the View menu, driving each window's `.inspector`.
            InspectorCommands()
        }
        // A refund or a purchase on another device can change while the app is in the background.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await pro.refresh() } }
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .preferredColorScheme(appearance.colorScheme)
                .environment(pro)
                .environment(ai)
        }
        #endif

        #if DEBUG && os(macOS)
        // Listed in the Window menu of debug builds only, for design review.
        Window(Text(verbatim: "Design System Gallery"), id: "design-system-gallery") {
            DesignSystemGallery()
        }
        #endif
    }
}

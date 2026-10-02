import SwiftUI
#if os(iOS)
import UIKit
#endif

@main
struct MindMapAIApp: App {
    static let mainWindowID = "main"

    @State private var launch = AppEnvironment.live()
    /// Shared by every window and Settings; the model itself loads on first use.
    @State private var ai = AIService()
    @AppStorage(AppearancePreference.storageKey, store: AppDefaults.store) private var appearance = AppearancePreference.system

    init() {
        // Before any view resolves a brand font by name.
        BrandFont.registerAll()
        #if os(iOS)
        // Transitions and keyboard animations too, which SwiftUI's Motion does not drive.
        if UITestMode.isActive { UIView.setAnimationsEnabled(false) }
        #endif
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
            .environment(ai)
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 760)
        #endif
        .commands { MapCommands(ai: ai) }

        #if os(macOS)
        Settings {
            SettingsView()
                .preferredColorScheme(appearance.colorScheme)
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

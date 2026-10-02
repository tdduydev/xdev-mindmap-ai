import AppIntents
import SwiftUI

@main
struct MindMapAIApp: App {
    static let mainWindowID = "main"

    @State private var launch: AppLaunch
    /// Shared by every window and Settings; the model itself loads on first use.
    @State private var ai = AIService()
    @AppStorage(AppearancePreference.storageKey) private var appearance = AppearancePreference.system

    init() {
        // Before any view resolves a brand font by name.
        BrandFont.registerAll()
        let launch = AppEnvironment.live()
        _launch = State(initialValue: launch)
        // Intents can run as soon as the app launches for them, before any window exists.
        if case .ready(let environment) = launch {
            let services = environment.intentServices()
            AppDependencyManager.shared.add(dependency: services)
        }
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
        .commands {
            MapCommands(ai: ai)
            // Show/Hide Inspector (⌃⌘I) in the View menu, driving each window's `.inspector`.
            InspectorCommands()
        }

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

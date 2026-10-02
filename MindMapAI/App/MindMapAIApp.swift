import SwiftUI

@main
struct MindMapAIApp: App {
    static let mainWindowID = "main"

    @State private var launch = AppEnvironment.live()
    @AppStorage(AppearancePreference.storageKey) private var appearance = AppearancePreference.system

    init() {
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
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 760)
        #endif
        .commands {
            MapCommands()
            // View ▸ Show/Hide Sidebar with ⌃⌘S, as the HIG lists for the View menu.
            SidebarCommands()
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .preferredColorScheme(appearance.colorScheme)
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

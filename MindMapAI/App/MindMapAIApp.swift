import SwiftUI

@main
struct MindMapAIApp: App {
    static let mainWindowID = "main"

    @State private var launch = AppEnvironment.live()
    @AppStorage(AppearancePreference.storageKey) private var appearance = AppearancePreference.system

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
        .commands { MapCommands() }

        #if os(macOS)
        Settings {
            SettingsView()
                .preferredColorScheme(appearance.colorScheme)
        }
        #endif
    }
}

import SwiftUI

@main
struct MindMapAIApp: App {
    @State private var launch = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            switch launch {
            case .ready(let environment):
                RootView(environment: environment)
            case .failed:
                StartupFailureView()
            }
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 760)
        #endif
    }
}

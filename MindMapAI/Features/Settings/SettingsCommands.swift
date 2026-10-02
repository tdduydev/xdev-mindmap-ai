#if os(iOS)
import SwiftUI

extension FocusedValues {
    /// Opens the in-app Settings sheet of the frontmost window.
    @Entry var showSettingsAction: ShowSettingsAction?
}

struct ShowSettingsAction {
    let perform: () -> Void
}

/// iPad's App menu: the system's Settings item opens this app's page in the
/// Settings app, so the in-app sheet gets its own item beneath it (HIG The menu
/// bar). No shortcut: ⌘, belongs to the system's item.
struct SettingsCommands: Commands {
    @FocusedValue(\.showSettingsAction) private var showSettings

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            Button("MindMap AI Settings…") { showSettings?.perform() }
                .disabled(showSettings == nil)
        }
    }
}
#endif

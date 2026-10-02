#if os(macOS)
import SwiftUI

/// Settings from the library window: the sidebar's footer and the toolbar.
/// ⌘, alone was hard to find (FR-SET-01); `SettingsLink` opens the same
/// Settings window as App ▸ Settings….
struct SettingsButton: View {
    let accessibilityID: String

    var body: some View {
        SettingsLink {
            Label("Settings", systemImage: "gearshape")
        }
        .help("Open Settings (⌘,)")
        .accessibilityIdentifier(accessibilityID)
    }
}
#endif

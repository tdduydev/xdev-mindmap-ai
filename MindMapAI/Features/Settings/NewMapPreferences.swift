import Foundation
import MindMapDomain

/// Settings ▸ General ▸ Theme for New Maps (FR-SET-02). A map keeps the theme
/// it was made with; changing it later is Change Theme in the editor.
enum NewMapPreferences {
    static let themeKey = "newMap.theme"

    /// The theme a new map gets. A Pro theme stored while Pro is missing (a
    /// refund, another Apple Account) gives Standard, and the stored choice
    /// stays, so it comes back once Pro does.
    static func theme(in defaults: UserDefaults = AppDefaults.store, entitlements: any ProEntitlements) -> MindMapTheme {
        let stored = defaults.string(forKey: themeKey).map(MindMapTheme.init(storedValue:)) ?? .standard
        if stored.requiresPro, !entitlements.allows(.extraThemes) { return .standard }
        return stored
    }
}

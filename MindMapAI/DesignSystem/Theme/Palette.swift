import SwiftUI

/// Brand and state colors. Each has light and dark values in the asset
/// catalog. Surfaces and text use system colors, so the app follows the platform.
enum Palette {
    /// xDev blue; also the app's tint (AccentColor).
    static let accent = Color.accentColor
    static let favorite = Color(.favorite)
    static let warningFill = Color(.warningFill)
    static let warningText = Color(.warningText)
}

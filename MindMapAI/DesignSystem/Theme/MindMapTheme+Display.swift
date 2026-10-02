import MindMapDomain
import SwiftUI

/// What the theme pickers show for each stored theme.
extension MindMapTheme: @retroactive Identifiable {
    public var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .standard: "Standard"
        case .xdevBlue: "xDev Blue"
        case .graphite: "Graphite"
        }
    }

    /// Themes beyond Standard belong to MindMap AI Pro (docs/pricing.md). Nothing
    /// asks yet: once MM-13's entitlement is on main, the pickers check
    /// `allows(.extraThemes)` for these and offer the paywall instead.
    var requiresPro: Bool { self != .standard }
}

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

    /// Themes beyond Standard belong to MindMap AI Pro (docs/pricing.md): every
    /// picker asks `allows(.extraThemes)` for these and offers the paywall instead.
    var requiresPro: Bool { self != .standard }
}

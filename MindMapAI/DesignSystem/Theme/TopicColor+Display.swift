import MindMapDomain
import SwiftUI

extension TopicColor {
    /// The colour behind the token: the Standard branch colours and graphite,
    /// so fills and badges derive through `BranchColors` and its contrast
    /// tests. A token from a newer version draws as graphite.
    var token: ColorToken {
        switch self {
        case .blue: BranchPalette.standard.colors[0]
        case .teal: BranchPalette.standard.colors[1]
        case .amber: BranchPalette.standard.colors[2]
        case .violet: BranchPalette.standard.colors[3]
        case .rose: BranchPalette.standard.colors[4]
        case .green: BranchPalette.standard.colors[5]
        default: BranchPalette.graphite.colors[0]
        }
    }

    /// The paired shape, so a colour is never told by hue alone.
    var shapeSymbol: String {
        switch self {
        case .blue: "circle.fill"
        case .teal: "square.fill"
        case .amber: "triangle.fill"
        case .violet: "diamond.fill"
        case .rose: "hexagon.fill"
        case .green: "seal.fill"
        default: "capsule.fill"
        }
    }

    var title: String {
        switch self {
        case .blue: String(localized: "Blue")
        case .teal: String(localized: "Teal")
        case .amber: String(localized: "Amber")
        case .violet: String(localized: "Violet")
        case .rose: String(localized: "Rose")
        case .green: String(localized: "Green")
        case .graphite: String(localized: "Graphite")
        default: String(localized: "Other Color")
        }
    }

    /// A tag chip's colours: the badge of its colour, graphite without one.
    static func chipColors(for color: TopicColor?, in variant: ColorVariant) -> BranchColors {
        BranchColors(line: (color ?? .graphite).token, variant: variant)
    }
}

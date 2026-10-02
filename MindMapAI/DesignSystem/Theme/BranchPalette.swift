import MindMapDomain
import SwiftUI

/// The line colours a theme gives its level-1 branches. Themes define only the
/// line colour; fills, strokes and badges are derived from it in `BranchColors`,
/// so a new theme needs no asset per derived colour.
struct BranchPalette: Hashable, Sendable {
    let colors: [ColorToken]

    /// The colour of the level-1 branch at `index` (in `sortOrder`), cycling
    /// after the last.
    func token(forBranch index: Int) -> ColorToken {
        let count = colors.count
        return colors[((index % count) + count) % count]
    }

    /// The xDev chart palette, darkened in light mode so every line reaches 4:1
    /// on the canvas.
    static let standard = BranchPalette(colors: [
        ColorToken(light: 0x0B6CF5, dark: 0x4AAEFF, lightHighContrast: 0x0954BF, darkHighContrast: 0x77C2FF), // blue
        ColorToken(light: 0x0B7F74, dark: 0x3CCFBE, lightHighContrast: 0x09635A, darkHighContrast: 0x6DDBCE), // teal
        ColorToken(light: 0xB26A00, dark: 0xFFC35C, lightHighContrast: 0x8B5300, darkHighContrast: 0xFFD285), // amber
        ColorToken(light: 0x6A4DF0, dark: 0xA594FF, lightHighContrast: 0x533CBB, darkHighContrast: 0xBCAFFF), // violet
        ColorToken(light: 0xC2385E, dark: 0xFF7FA0, lightHighContrast: 0x972C49, darkHighContrast: 0xFF9FB8), // rose
        ColorToken(light: 0x1F8A55, dark: 0x4ADE9B, lightHighContrast: 0x186C42, darkHighContrast: 0x77E6B4), // green
    ])
}

/// A map's look. Themes change colour only, never layout, fonts or shapes.
struct MapTheme: Hashable, Sendable {
    let branches: BranchPalette

    static let standard = MapTheme(branches: .standard)

    /// The theme stored on the map. xDev Blue and Graphite come with MM-18.
    init(_ theme: MindMapTheme) {
        switch theme {
        case .standard: self = .standard
        }
    }

    private init(branches: BranchPalette) {
        self.branches = branches
    }

    func branch(_ index: Int, in variant: ColorVariant) -> BranchColors {
        BranchColors(line: branches.token(forBranch: index), variant: variant)
    }
}

/// The colours of one branch in one appearance, derived from its line colour.
struct BranchColors: Hashable, Sendable {
    /// The line colour, for strokes and edges (the IC value with Increase Contrast).
    let line: SRGBColor
    /// Level-1 fill, opaque, over the canvas.
    let mainFill: SRGBColor
    /// Level-2 and deeper fill, opaque, over the canvas.
    let subFill: SRGBColor
    let badgeFill: SRGBColor
    let badgeText: SRGBColor

    init(line token: ColorToken, variant: ColorVariant) {
        let canvas = Palette.Tokens.canvasBackground[variant]
        let line = token[variant]
        self.line = line
        mainFill = line.composited(over: canvas, opacity: Self.mainFillOpacity(variant))
        subFill = line.composited(over: canvas, opacity: Self.subFillOpacity(variant))
        // In light mode the badge takes the deeper IC colour so white text reads at 6.3:1 or more.
        badgeFill = variant == .light ? token.lightHighContrast : line
        badgeText = Palette.Tokens.badgeText[variant]
    }

    static func mainFillOpacity(_ variant: ColorVariant) -> Double {
        switch variant {
        case .light: 0.12
        case .dark: 0.20
        case .lightHighContrast: 0.18
        case .darkHighContrast: 0.28
        }
    }

    static func subFillOpacity(_ variant: ColorVariant) -> Double {
        switch variant {
        case .light: 0.07
        case .dark: 0.12
        case .lightHighContrast: 0.12
        case .darkHighContrast: 0.20
        }
    }
}

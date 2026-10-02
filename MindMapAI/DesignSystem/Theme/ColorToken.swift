import Foundation
import SwiftUI

/// An opaque sRGB colour with the arithmetic the design system needs: WCAG
/// contrast for the tests, and compositing so derived fills stay opaque (a
/// translucent fill would let edges show through the topics drawn over them).
/// Not named `RGBColor`: AppKit re-exports QuickDraw's `RGBColor`, and any file
/// importing both AppKit and this module could no longer name the type.
struct SRGBColor: Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// `0xRRGGBB`, the form the design-system tables use.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }

    /// WCAG 2 relative luminance.
    var relativeLuminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG 2 contrast ratio, 1 to 21.
    func contrast(with other: SRGBColor) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// This colour at `opacity` over `background`, flattened to an opaque colour.
    func composited(over background: SRGBColor, opacity: Double) -> SRGBColor {
        SRGBColor(
            red: red * opacity + background.red * (1 - opacity),
            green: green * opacity + background.green * (1 - opacity),
            blue: blue * opacity + background.blue * (1 - opacity)
        )
    }
}

/// The four appearances every custom colour defines (design system, principle 4).
enum ColorVariant: CaseIterable, Sendable {
    case light, dark, lightHighContrast, darkHighContrast

    init(colorScheme: ColorScheme, contrast: ColorSchemeContrast) {
        switch (colorScheme, contrast) {
        case (.dark, .increased): self = .darkHighContrast
        case (.dark, _): self = .dark
        case (_, .increased): self = .lightHighContrast
        default: self = .light
        }
    }

    var isDark: Bool { self == .dark || self == .darkHighContrast }
    var isHighContrast: Bool { self == .lightHighContrast || self == .darkHighContrast }
}

/// One colour role with its four values.
struct ColorToken: Hashable, Sendable {
    let light: SRGBColor
    let dark: SRGBColor
    let lightHighContrast: SRGBColor
    let darkHighContrast: SRGBColor

    init(light: UInt32, dark: UInt32, lightHighContrast: UInt32, darkHighContrast: UInt32) {
        self.light = SRGBColor(hex: light)
        self.dark = SRGBColor(hex: dark)
        self.lightHighContrast = SRGBColor(hex: lightHighContrast)
        self.darkHighContrast = SRGBColor(hex: darkHighContrast)
    }

    subscript(variant: ColorVariant) -> SRGBColor {
        switch variant {
        case .light: light
        case .dark: dark
        case .lightHighContrast: lightHighContrast
        case .darkHighContrast: darkHighContrast
        }
    }
}

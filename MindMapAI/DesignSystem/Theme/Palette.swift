import SwiftUI

/// Semantic colours. Each is an asset catalog colour set named after its token,
/// with Any, Dark and High Contrast appearances, so views pick up the system's
/// appearance and Increase Contrast without code. Chrome surfaces and text use
/// system colours, so the app still follows the platform.
enum Palette {
    /// xDev blue; also the app's tint (AccentColor). The selection ring uses it too.
    static let accent = Color.accentColor
    static let selectionRing = Color.accentColor
    static let favorite = Color(.favorite)
    static let warningFill = Color(.warningFill)
    static let warningText = Color(.warningText)
    static let danger = Color(.danger)
    static let success = Color(.success)

    // Canvas
    static let canvasBackground = Color(.canvasBackground)
    static let topicText = Color(.topicText)
    static let topicTextSecondary = Color(.topicTextSecondary)
    static let centralFill = Color(.centralFill)
    static let centralText = Color(.centralText)
    static let crossLink = Color(.crossLink)
    /// Callout bubble (FR-ORG-30); its outline and tail use `calloutStroke`.
    static let calloutFill = Color(.calloutFill)
    static let calloutStroke = crossLink
    static let searchMatchFill = Color(.searchMatchFill)
    static let searchMatchBorder = Color(.searchMatchBorder)

    /// The AI signature: the xDev gradient at 135°, or a solid colour with
    /// Increase Contrast or Reduce Transparency. Only for symbols, outlines and
    /// progress, never behind text and never on glass.
    static func ai(colorScheme: ColorScheme, contrast: ColorSchemeContrast, reduceTransparency: Bool) -> AnyShapeStyle {
        let variant = ColorVariant(colorScheme: colorScheme, contrast: contrast)
        if variant.isHighContrast || reduceTransparency {
            return AnyShapeStyle(Tokens.aiSolid[variant].color)
        }
        let stops = variant.isDark ? Tokens.aiGradientDark : Tokens.aiGradientLight
        return AnyShapeStyle(LinearGradient(
            colors: stops.map(\.color),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ))
    }

    /// The values behind the colour sets, for code that must compute with a
    /// colour (opaque derived fills, contrast tests). A test checks that every
    /// colour set in the asset catalog matches its token here.
    enum Tokens {
        static let canvasBackground = ColorToken(light: 0xF7F9FC, dark: 0x142745, lightHighContrast: 0xFFFFFF, darkHighContrast: 0x0B1830)
        static let topicText = ColorToken(light: 0x22314F, dark: 0xF4F6FC, lightHighContrast: 0x0C1A33, darkHighContrast: 0xFFFFFF)
        static let topicTextSecondary = ColorToken(light: 0x5B6885, dark: 0x9DAAC7, lightHighContrast: 0x344568, darkHighContrast: 0xE8ECF8)
        static let centralFill = ColorToken(light: 0x142745, dark: 0xE8ECF8, lightHighContrast: 0x0B1830, darkHighContrast: 0xFFFFFF)
        static let centralText = ColorToken(light: 0xFFFFFF, dark: 0x142745, lightHighContrast: 0xFFFFFF, darkHighContrast: 0x0B1830)
        static let accent = ColorToken(light: 0x004CFF, dark: 0x4AAEFF, lightHighContrast: 0x0038C2, darkHighContrast: 0x7BD4FF)
        static let crossLink = ColorToken(light: 0x5B6885, dark: 0x9DAAC7, lightHighContrast: 0x344568, darkHighContrast: 0xE8ECF8)
        static let calloutFill = ColorToken(light: 0xEEF2FA, dark: 0x1E3358, lightHighContrast: 0xFFFFFF, darkHighContrast: 0x0B1830)
        static let searchMatchFill = ColorToken(light: 0xFFF4DB, dark: 0x3D3423, lightHighContrast: 0xFFE7B3, darkHighContrast: 0x4A3B1E)
        static let searchMatchBorder = ColorToken(light: 0xB26A00, dark: 0xFFC35C, lightHighContrast: 0x8B5300, darkHighContrast: 0xFFD285)
        static let favorite = ColorToken(light: 0xB26A00, dark: 0xFFC35C, lightHighContrast: 0x9A5B00, darkHighContrast: 0xFFD285)
        static let warningFill = ColorToken(light: 0xFFF4DB, dark: 0x3D3423, lightHighContrast: 0xFFE7B3, darkHighContrast: 0x4A3B1E)
        static let warningText = ColorToken(light: 0x9A5B00, dark: 0xFFC35C, lightHighContrast: 0x7A4600, darkHighContrast: 0xFFD285)
        static let danger = ColorToken(light: 0xC62828, dark: 0xFF8A8A, lightHighContrast: 0xA51F1F, darkHighContrast: 0xFFB4B4)
        static let success = ColorToken(light: 0x0F7A4A, dark: 0x4ADE9B, lightHighContrast: 0x0B5E39, darkHighContrast: 0x7EE2A8)

        /// Text on a collapse badge: white on the deep light badge, navy on the
        /// bright dark one.
        static let badgeText = ColorToken(light: 0xFFFFFF, dark: 0x142745, lightHighContrast: 0xFFFFFF, darkHighContrast: 0x0B1830)

        static let aiGradientLight = [SRGBColor(hex: 0x1E90FF), SRGBColor(hex: 0x004CFF)]
        static let aiGradientDark = [SRGBColor(hex: 0x7BD4FF), SRGBColor(hex: 0x4AAEFF)]
        /// Solid AI colour; the first two values are the fallback for Reduce Transparency.
        static let aiSolid = ColorToken(light: 0x0038C2, dark: 0x7BD4FF, lightHighContrast: 0x0038C2, darkHighContrast: 0x7BD4FF)

        /// Colour set name to token, for the asset catalog check.
        static let colorSets: [String: ColorToken] = [
            "AccentColor": accent,
            "CanvasBackground": canvasBackground,
            "TopicText": topicText,
            "TopicTextSecondary": topicTextSecondary,
            "CentralFill": centralFill,
            "CentralText": centralText,
            "CrossLink": crossLink,
            "CalloutFill": calloutFill,
            "SearchMatchFill": searchMatchFill,
            "SearchMatchBorder": searchMatchBorder,
            "Favorite": favorite,
            "WarningFill": warningFill,
            "WarningText": warningText,
            "Danger": danger,
            "Success": success,
        ]
    }
}

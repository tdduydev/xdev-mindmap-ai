import SwiftUI

/// The map is flat; only a dragged topic lifts. Floating controls use system
/// glass and its own shadow, so they have no token here.
enum Elevation {
    struct Shadow: Hashable, Sendable {
        let color: SRGBColor
        let opacity: Double
        /// Blur as written in the xDev tokens (CSS `box-shadow` blur).
        let blur: CGFloat
        let y: CGFloat

        static let flat = Shadow(color: SRGBColor(hex: 0x000000), opacity: 0, blur: 0, y: 0)
    }

    /// A key shadow and a tighter ambient one; dark mode has only the key.
    static func drag(colorScheme: ColorScheme) -> (key: Shadow, ambient: Shadow) {
        if colorScheme == .dark {
            return (Shadow(color: SRGBColor(hex: 0x000000), opacity: 0.45, blur: 24, y: 8), .flat)
        }
        let navy = SRGBColor(hex: 0x142745)
        return (Shadow(color: navy, opacity: 0.18, blur: 24, y: 8), Shadow(color: navy, opacity: 0.08, blur: 6, y: 2))
    }
}

private struct DragElevation: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shadows = Elevation.drag(colorScheme: colorScheme)
        return content
            .elevationShadow(shadows.key)
            .elevationShadow(shadows.ambient)
    }
}

private extension View {
    // A CSS blur spreads about twice as far as SwiftUI's radius, so halve it.
    // An approximation; compare with the web tokens when the canvas lands (MM-3).
    func elevationShadow(_ shadow: Elevation.Shadow) -> some View {
        self.shadow(color: shadow.color.color.opacity(shadow.opacity), radius: shadow.blur / 2, y: shadow.y)
    }
}

extension View {
    /// The lifted look of a topic following the pointer.
    func dragElevation() -> some View {
        modifier(DragElevation())
    }
}

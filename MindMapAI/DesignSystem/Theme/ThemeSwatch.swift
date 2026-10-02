import MindMapDomain
import SwiftUI

/// A row of the branch colours a theme gives, so a picker shows the colours
/// rather than only a name. Decorative: the theme's name is the label.
struct ThemeSwatch: View {
    let theme: MindMapTheme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    /// Diameter of one colour dot.
    static let dotSize: CGFloat = 10

    var body: some View {
        let variant = ColorVariant(colorScheme: colorScheme, contrast: contrast)
        let palette = MapTheme(theme).branches
        HStack(spacing: Spacing.xxs) {
            ForEach(palette.colors.indices, id: \.self) { index in
                Circle()
                    .fill(palette.colors[index][variant].color)
                    .frame(width: Self.dotSize, height: Self.dotSize)
            }
        }
        .accessibilityHidden(true)
    }
}

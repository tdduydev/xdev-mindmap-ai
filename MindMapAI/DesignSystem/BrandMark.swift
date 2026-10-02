import SwiftUI

/// The app's logo in the interface: the icon artwork and, in the lockup, the
/// "MindMap AI" wordmark set in the brand face with "by xDev" under it. The
/// wordmark is live text rather than the SVG in `docs/brand`, because an asset
/// catalog does not draw an SVG's text and live text follows the locale.
///
/// For first-run, About and recovery screens only. The HIG keeps a logo out of
/// sidebars and toolbars, where it would take space from the person's content.
struct BrandMark: View {
    enum Style {
        /// Icon with the wordmark beside it.
        case lockup
        /// The icon alone.
        case icon
    }

    enum Size {
        /// About and the library's empty state.
        case regular
        /// Beside a message, such as the storage recovery screen.
        case small

        var iconLength: CGFloat {
            switch self {
            case .regular: BrandMarkMetrics.regularIcon
            case .small: BrandMarkMetrics.smallIcon
            }
        }

        var wordmark: ContentStyle {
            switch self {
            case .regular: Typography.Content.display
            case .small: Typography.Content.central
            }
        }
    }

    /// What VoiceOver reads for the whole mark, once.
    static let accessibilityName: LocalizedStringResource = "MindMap AI by xDev"

    var style: Style = .lockup
    var size: Size = .regular

    var body: some View {
        HStack(spacing: Spacing.md) {
            icon
            if style == .lockup {
                wordmark
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Self.accessibilityName))
        .accessibilityAddTraits(.isImage)
    }

    private var icon: some View {
        Image(.brandMark)
            .resizable()
            .interpolation(.high)
            .frame(width: size.iconLength, height: size.iconLength)
            // The artwork is a full square; the system masks the app icon, so
            // the interface does the same to match what is in the Dock.
            .clipShape(RoundedRectangle(cornerRadius: size.iconLength * BrandMarkMetrics.cornerRatio, style: .continuous))
    }

    private var wordmark: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            // Brand names stay as written in every language.
            Text(verbatim: "MindMap AI")
                .font(size.wordmark.font)
                .foregroundStyle(.primary)
            Text(verbatim: "by xDev")
                .font(Typography.brandByline)
                .foregroundStyle(.secondary)
        }
        .fixedSize()
    }
}

/// Sizes of the brand mark, in points.
enum BrandMarkMetrics {
    static let regularIcon: CGFloat = 64
    static let smallIcon: CGFloat = 32
    /// Corner radius over side of the app icon's rounded square.
    static let cornerRatio: CGFloat = 0.225
}

#Preview("Lockup") {
    VStack(spacing: Spacing.xl) {
        BrandMark()
        BrandMark(style: .icon, size: .small)
    }
    .padding(Spacing.xl)
}

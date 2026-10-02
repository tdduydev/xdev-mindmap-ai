import CoreGraphics

/// The spacing scale, on the xDev 4-point grid. Views use these names, never
/// raw numbers, so the whole app can be retuned in one place.
enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32

    /// Horizontal step for each level of the outline.
    static let outlineIndent: CGFloat = 20
}

/// Corner radii, from the xDev scale.
enum Radius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
}

/// Fixed control sizes.
enum Metrics {
    /// Square frame of the outline's expand/collapse control.
    static let disclosureSize: CGFloat = 20

    /// Smallest tappable area: 44 pt for touch (HIG), less for a pointer.
    #if os(iOS)
    static let minimumHitTarget: CGFloat = 44
    #else
    static let minimumHitTarget: CGFloat = 24
    #endif

    /// Width of the Mac Settings window.
    static let settingsWidth: CGFloat = 480

    /// Width of the paywall sheet on the Mac.
    static let paywallWidth: CGFloat = 420
}

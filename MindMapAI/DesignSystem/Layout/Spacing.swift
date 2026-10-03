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
    static let onboardingWidth: CGFloat = 440
    static let onboardingHeight: CGFloat = 360
    /// Square frame of the outline's expand/collapse control.
    static let disclosureSize: CGFloat = 20

    /// Smallest tappable area: 44 pt for touch (HIG), less for a pointer.
    #if os(iOS)
    static let minimumHitTarget: CGFloat = 44
    #else
    static let minimumHitTarget: CGFloat = 24
    #endif

    /// Room for "400%" in the canvas controls, so the cluster does not resize while zooming.
    static let zoomLabelWidth: CGFloat = 48

    /// Width of the Mac Settings window: wide enough for all eight pane tabs
    /// in Vietnamese, the longest titles, or Privacy and About fall into the
    /// toolbar's overflow menu (MM-93).
    static let settingsWidth: CGFloat = 560

    /// Width of the paywall sheet on the Mac.
    static let paywallWidth: CGFloat = 420
    /// The AI suggestion review popover.
    static let suggestionListWidth: CGFloat = 320
    static let suggestionListHeight: CGFloat = 280
    /// AI sheets on the Mac, where a sheet takes its content's size.
    static let aiSheetWidth: CGFloat = 440
    /// The Mac's Keyboard Shortcuts sheet.
    static let shortcutsSheetSize = CGSize(width: 480, height: 560)

    /// File ▸ Export… on the Mac.
    static let exportSheetWidth: CGFloat = 440
    /// Settings ▸ AI Apps ▸ Add App…: wide enough for a config snippet's longest line.
    static let addAppSheetWidth: CGFloat = 520
    /// The port field, five digits.
    static let portFieldWidth: CGFloat = 72

    /// Room for a few lines of note in the inspector before it grows.
    static let noteEditorMinHeight: CGFloat = 120

    /// The progress bar in the inspector's Task section, beside its "3 of 5 done".
    static let taskProgressBarWidth: CGFloat = 80

    /// Room for a typical URL in the Add Link sheet.
    static let linkSheetMinWidth: CGFloat = 420
    /// Share Link… on the Mac: room for the scope picker and the privacy lines (MM-113).
    static let shareLinkSheetMinWidth: CGFloat = 420
    static let shareLinkSheetMinHeight: CGFloat = 260
    /// Open Map Link… on the Mac: a whole map link is long, so the field is wider.
    static let openMapLinkSheetMinWidth: CGFloat = 460
    /// The Add Connection target picker on the Mac: room for a topic path.
    static let connectionPickerSize = CGSize(width: 420, height: 480)

    /// Topic ▸ Tags ▸ Manage Tags… on the Mac.
    static let tagManagerSize = CGSize(width: 440, height: 480)

    /// Format ▸ Topic Symbol ▸ Choose Symbol… on the Mac: eight symbols a row.
    static let symbolPickerWidth: CGFloat = 460
    static let symbolPickerHeight: CGFloat = 520
}

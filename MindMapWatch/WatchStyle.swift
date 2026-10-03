import SwiftUI

/// The watch's share of the design system. The app's `DesignSystem` lives in
/// the app target, so the few values the watch needs are named here instead
/// of written as numbers in views.
enum WatchStyle {
    /// Space between a symbol and its text in a notice.
    static let noticeSpacing: CGFloat = 4
    /// The brand blue, the same as the app's accent colour.
    static let accent = Color.accentColor
}

extension WatchStyle {
    /// How long "Added to Inbox" stays before the list comes back.
    static let confirmationDuration = Duration.seconds(1.5)
}

extension WatchStyle {
    /// Outline indent per level, capped so deep branches still fit the screen.
    static let indentPerLevel: CGFloat = 8
    static let maximumIndentLevels = 4
}

import SwiftUI

/// Text styles by role. Chrome (sidebar, lists, toolbar, menus, Settings) uses
/// system text styles, so it follows Dynamic Type on iOS and the user's text
/// size on macOS. Map content uses the brand fonts in `Typography.Content`.
enum Typography {
    static let rootTopic = Font.title3.weight(.semibold)
    static let topic = Font.body
    static let rowTitle = Font.body.weight(.medium)
    static let rowDetail = Font.subheadline
    static let banner = Font.callout

    /// Brand fonts for the canvas, the outline's topics, notes and display
    /// headlines. Each scales with Dynamic Type on iOS and iPadOS through
    /// `relativeTo`; macOS has no Dynamic Type and uses the size as is.
    enum Content {
        static let central = ContentStyle(.spaceGroteskSemiBold, size: 20, lineHeight: 26, relativeTo: .title3)
        static let main = ContentStyle(.beVietnamProSemiBold, size: 15, lineHeight: 20, relativeTo: .body)
        static let sub = ContentStyle(.beVietnamProRegular, size: 14, lineHeight: 19, relativeTo: .callout)
        static let deep = ContentStyle(.beVietnamProRegular, size: 13, lineHeight: 18, relativeTo: .subheadline)
        static let outlineTopic = ContentStyle(.beVietnamProRegular, size: 14, lineHeight: 20, relativeTo: .body)
        static let outlineRoot = ContentStyle(.beVietnamProSemiBold, size: 14, lineHeight: 20, relativeTo: .body)
        static let note = ContentStyle(.beVietnamProRegular, size: 14, lineHeight: 21, relativeTo: .body)
        static let badge = ContentStyle(.beVietnamProSemiBold, size: 11, lineHeight: 14, relativeTo: .caption2, tabularDigits: true)
        static let display = ContentStyle(.spaceGroteskSemiBold, size: 28, lineHeight: 34, relativeTo: .largeTitle)

        /// The topic style for a level: 0 is the central topic.
        static func topic(level: Int) -> ContentStyle {
            switch level {
            case ...0: central
            case 1: main
            case 2: sub
            default: deep
            }
        }
    }
}

/// One content text style: a brand face at a canvas size (100% zoom) and the
/// line height the layout reserves for it.
struct ContentStyle: Hashable {
    let face: BrandFont
    let size: CGFloat
    let lineHeight: CGFloat
    let textStyle: Font.TextStyle
    let tabularDigits: Bool

    init(_ face: BrandFont, size: CGFloat, lineHeight: CGFloat, relativeTo textStyle: Font.TextStyle, tabularDigits: Bool = false) {
        self.face = face
        self.size = size
        self.lineHeight = lineHeight
        self.textStyle = textStyle
        self.tabularDigits = tabularDigits
    }

    var font: Font {
        let font = Font.custom(face.postScriptName, size: size, relativeTo: textStyle)
        return tabularDigits ? font.monospacedDigit() : font
    }

    /// Extra space between lines to reach `lineHeight`, assuming a natural line
    /// of 1.2 times the size. An approximation until the canvas (MM-3) measures
    /// the real line from the font's metrics.
    var lineSpacing: CGFloat { max(0, lineHeight - size * 1.2) }
}

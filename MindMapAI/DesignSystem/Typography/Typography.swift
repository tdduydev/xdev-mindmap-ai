import SwiftUI

/// Text styles by role. All are system text styles, so they follow Dynamic Type
/// on iOS and the user's text size on macOS.
enum Typography {
    static let rootTopic = Font.title3.weight(.semibold)
    static let topic = Font.body
    static let rowTitle = Font.body.weight(.medium)
    static let rowDetail = Font.subheadline
    static let banner = Font.callout
}

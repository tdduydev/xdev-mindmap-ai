#if os(iOS)
import SwiftUI
import UIKit

/// Two-finger scrolling on an iPad trackpad or mouse pans the canvas. Touch
/// drags are left to the SwiftUI drag gesture, so this recognizer takes scroll
/// input only.
struct CanvasScrollInput: UIGestureRecognizerRepresentable {
    let model: CanvasModel

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.allowedScrollTypesMask = .all
        recognizer.allowedTouchTypes = []
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = recognizer.translation(in: recognizer.view)
        recognizer.setTranslation(.zero, in: recognizer.view)
        model.pan(by: CGSize(width: translation.x, height: translation.y))
    }
}

extension Font.TextStyle {
    /// The UIKit style, for scaling a content font with `UIFontMetrics`.
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .body: .body
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .largeTitle
        }
    }
}
#endif

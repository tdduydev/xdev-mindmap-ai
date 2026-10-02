#if os(iOS)
import UIKit

/// The general pasteboard, as plain text: Markdown is text, and every app can paste it.
final class SystemClipboard: TextClipboard {
    var text: String? { UIPasteboard.general.string }
    var hasText: Bool { UIPasteboard.general.hasStrings }

    func setText(_ text: String) {
        UIPasteboard.general.string = text
    }
}
#endif

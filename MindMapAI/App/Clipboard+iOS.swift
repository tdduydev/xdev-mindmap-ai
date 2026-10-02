#if os(iOS)
import UIKit

/// The general pasteboard's text, for Map from Clipboard and chat Copy. iOS asks the user
/// before handing it over, the first time and whenever they have not allowed
/// pasting from other apps.
enum Clipboard {
    static var string: String? {
        UIPasteboard.general.string
    }

    /// Puts plain text on the pasteboard, as Copy on a chat answer does.
    static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }
}
#endif

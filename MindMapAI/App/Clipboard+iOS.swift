#if os(iOS)
import UIKit

/// The general pasteboard's text, for Map from Clipboard. iOS asks the user
/// before handing it over, the first time and whenever they have not allowed
/// pasting from other apps.
enum Clipboard {
    static var string: String? {
        UIPasteboard.general.string
    }
}
#endif

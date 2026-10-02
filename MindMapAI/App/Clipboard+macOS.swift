#if os(macOS)
import AppKit

/// The general pasteboard's text, for Map from Clipboard and chat Copy.
enum Clipboard {
    static var string: String? {
        NSPasteboard.general.string(forType: .string)
    }

    /// Puts plain text on the pasteboard, as Copy on a chat answer does.
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
#endif

#if os(macOS)
import AppKit

/// The general pasteboard's text, for Map from Clipboard.
enum Clipboard {
    static var string: String? {
        NSPasteboard.general.string(forType: .string)
    }
}
#endif

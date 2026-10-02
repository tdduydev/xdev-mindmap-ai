#if os(macOS)
import AppKit

/// The general pasteboard, as plain text: Markdown is text, and every app can paste it.
final class SystemClipboard: TextClipboard {
    var text: String? { NSPasteboard.general.string(forType: .string) }
    var hasText: Bool { NSPasteboard.general.availableType(from: [.string]) != nil }

    func setText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
#endif

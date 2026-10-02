#if os(macOS)
import AppKit
import SwiftUI

/// The window a view is in, for bringing it to the front.
final class WindowHandle {
    fileprivate weak var window: NSWindow?

    func activate() {
        window?.makeKeyAndOrderFront(nil)
    }
}

struct WindowReader: NSViewRepresentable {
    let handle: WindowHandle

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.handle = handle
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {}

    final class ReaderView: NSView {
        var handle: WindowHandle?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            handle?.window = window
        }
    }
}
#endif

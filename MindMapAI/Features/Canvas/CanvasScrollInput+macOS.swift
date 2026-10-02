#if os(macOS)
import AppKit
import SwiftUI

/// Two-finger trackpad scrolling and the mouse wheel pan the canvas; with ⌘
/// held they zoom around the pointer.
///
/// SwiftUI has no scroll-wheel gesture for a custom view, and a scroll event
/// over a topic goes to the hosting view rather than to a background NSView,
/// so this watches the window's scroll events and takes the ones over its frame.
struct CanvasScrollInput: NSViewRepresentable {
    let model: CanvasModel

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.model = model
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.model = model
    }

    final class MonitorView: NSView {
        weak var model: CanvasModel?
        private var monitor: Any?

        // Top-left origin, like SwiftUI, so pointer locations match the viewport.
        override var isFlipped: Bool { true }

        // Clicks go through to the canvas; only scroll events are watched.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }
            // Local monitors run on the main thread.
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                let handled = MainActor.assumeIsolated { self?.handle(event) ?? false }
                return handled ? nil : event
            }
        }

        private func handle(_ event: NSEvent) -> Bool {
            guard let model, event.window === window, !isHiddenOrHasHiddenAncestor else { return false }
            let location = convert(event.locationInWindow, from: nil)
            guard bounds.contains(location) else { return false }

            let step = event.hasPreciseScrollingDeltas ? 1 : CanvasMetrics.wheelLineStep
            let delta = CGSize(width: event.scrollingDeltaX * step, height: event.scrollingDeltaY * step)
            if event.modifierFlags.contains(.command) {
                model.zoom(to: model.viewport.scale * exp(delta.height * CanvasMetrics.wheelZoomRate), anchor: location)
            } else {
                model.pan(by: delta)
            }
            return true
        }
    }
}
#endif

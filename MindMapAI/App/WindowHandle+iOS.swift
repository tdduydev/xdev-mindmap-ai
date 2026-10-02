#if os(iOS)
import SwiftUI
import UIKit

/// The scene a view is in, for bringing its window to the front (on iPad,
/// out of Stage Manager or another space).
final class WindowHandle {
    fileprivate weak var scene: UIWindowScene?

    func activate() {
        guard let scene else { return }
        UIApplication.shared.activateSceneSession(for: UISceneSessionActivationRequest(session: scene.session)) { error in
            Log.windows.error("Bringing a window to the front failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

struct WindowReader: UIViewRepresentable {
    let handle: WindowHandle

    func makeUIView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.handle = handle
        return view
    }

    func updateUIView(_ view: ReaderView, context: Context) {}

    final class ReaderView: UIView {
        var handle: WindowHandle?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            handle?.scene = window?.windowScene
        }
    }
}
#endif

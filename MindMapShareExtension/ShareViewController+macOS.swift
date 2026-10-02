#if os(macOS)
import AppKit
import SwiftUI

/// The extension's entry point on macOS (`NSExtensionPrincipalClass`).
final class ShareViewController: NSViewController {
    private let model = ShareModel.live()

    override func loadView() {
        view = NSHostingView(rootView: ShareView(model: model) { [weak self] saved in
            self?.finish(saved: saved)
        })
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        Task { await model.load(from: items) }
    }

    private func finish(saved: Bool) {
        if saved {
            extensionContext?.completeRequest(returningItems: nil)
        } else {
            extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        }
    }
}
#endif

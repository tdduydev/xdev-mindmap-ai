#if os(iOS)
import SwiftUI
import UIKit

/// The extension's entry point on iOS and iPadOS (`NSExtensionPrincipalClass`).
final class ShareViewController: UIViewController {
    private let model = ShareModel.live()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareView(model: model) { [weak self] saved in
            self?.finish(saved: saved)
        })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

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

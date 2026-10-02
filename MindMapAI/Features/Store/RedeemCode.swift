import StoreKit
import SwiftUI

extension FocusedValues {
    /// Redeem Code… in the frontmost window.
    @Entry var redeemCodeAction: RedeemCodeAction?
}

struct RedeemCodeAction {
    let perform: () -> Void
}

/// Redeem Code… under Settings in the app menu. Gift codes are Apple's offer
/// codes: App Review 3.1.1 rules out a license key of our own.
struct RedeemCodeCommands: Commands {
    let pro: ProEntitlement
    @FocusedValue(\.redeemCodeAction) private var redeem

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            Button("Redeem Code…") { redeem?.perform() }
                .disabled(redeem == nil || pro.isUnlocked)
        }
    }
}

extension View {
    /// Apple's offer code sheet and what the app says when it fails.
    func redeemCodeSheet(isPresented: Binding<Bool>) -> some View {
        modifier(RedeemCodePresenter(isPresented: isPresented))
    }

    /// A window root: lets Redeem Code… in the menu open the sheet on this window.
    func redeemCodeCommandTarget() -> some View {
        modifier(RedeemCodeCommandTarget())
    }
}

private struct RedeemCodeCommandTarget: ViewModifier {
    @State private var isRedeeming = false

    func body(content: Content) -> some View {
        content
            .redeemCodeSheet(isPresented: $isRedeeming)
            .focusedSceneValue(\.redeemCodeAction, RedeemCodeAction { isRedeeming = true })
    }
}

private struct RedeemCodePresenter: ViewModifier {
    @Binding var isPresented: Bool
    @Environment(ProEntitlement.self) private var store
    @Environment(\.openURL) private var openURL
    /// Kept here, not in the store, so only the window that opened the sheet shows the alert.
    @State private var didFail = false

    func body(content: Content) -> some View {
        presentingSheet(content)
            .alert("Couldn’t Redeem the Code", isPresented: $didFail) {
                Button("Redeem in App Store") { openURL(AppLinks.redeemCode) }
                Button("OK", role: .cancel) {}
            } message: {
                Text("Check the code and your connection, then try again. You can also redeem it on the App Store.")
            }
    }

    @ViewBuilder
    private func presentingSheet(_ content: Content) -> some View {
        if #available(iOS 27, macOS 27, *) {
            content.offerCodeRedemption(options: [], isPresented: $isPresented) { result in
                Task { finish(await store.finishRedemption(transaction: result)) }
            }
        } else {
            content.offerCodeRedemption(isPresented: $isPresented) { result in
                Task { finish(await store.finishRedemption(result)) }
            }
        }
    }

    private func finish(_ outcome: ProEntitlement.RedeemOutcome) {
        didFail = outcome == .failed
    }
}

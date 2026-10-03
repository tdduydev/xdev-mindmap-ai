import MindMapAICore
import StoreKit
import SwiftUI

/// What Pro costs and what it unlocks, stated before the purchase button
/// (App Review 3.1.1). Closing it never blocks anything: core mind mapping is free.
struct PaywallView: View {
    /// The feature that led here, listed first; nil when opened from Settings.
    var feature: ProFeature?

    @Environment(ProEntitlement.self) private var store
    /// Optional so the paywall can be drawn on its own (the App Review
    /// screenshot); without it the paywall lists AI tools.
    @Environment(AIService.self) private var ai: AIService?
    @Environment(\.purchase) private var purchase
    @Environment(\.dismiss) private var dismiss
    @State private var isRedeeming = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("MindMap AI Pro")
                            .font(Typography.paywallTitle)
                        Group {
                            if includesAI {
                                Text("Pro adds extra export formats, themes, AI tools and voice input. Maps, topics and everything else stay free.")
                            } else {
                                Text("Pro adds extra export formats, themes and voice input. Maps, topics and everything else stay free.")
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, Spacing.xs)
                }

                Section("Included in Pro") {
                    ForEach(features) { item in
                        Label {
                            Text(item.title)
                        } icon: {
                            Image(systemName: item.systemImage)
                                .foregroundStyle(Palette.accent)
                        }
                        .accessibilityIdentifier(AccessibilityID.Paywall.feature)
                    }
                }

                Section {
                    purchaseRow
                    Button("Restore Purchases") {
                        Task { await store.restorePurchases() }
                    }
                    .disabled(store.restoreState == .restoring)
                    .accessibilityIdentifier(AccessibilityID.Paywall.restore)
                    if !store.isUnlocked {
                        Button("Redeem Code…") { isRedeeming = true }
                    }
                } footer: {
                    Text("A one-time purchase, not a subscription. Payment is charged to your Apple Account.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("MindMap AI Pro")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(store.isUnlocked ? "Done" : "Not Now") { dismiss() }
                        .accessibilityIdentifier(AccessibilityID.Paywall.close)
                }
            }
            .restoreResultAlert(store)
            .redeemCodeSheet(isPresented: $isRedeeming)
        }
        #if os(macOS)
        .frame(width: Metrics.paywallWidth)
        .frame(minHeight: Metrics.paywallWidth)
        #endif
        .task {
            if store.product == nil { await store.loadProduct() }
        }
    }

    /// False only once the device is known to never run the model, as for
    /// every other AI entry point (FR-AI-02).
    private var includesAI: Bool { ai?.capabilities?.showsAIEntryPoints ?? true }

    private var features: [ProFeature] {
        let offered = ProFeature.offered(includingAI: includesAI)
        guard let feature, offered.contains(feature) else { return offered }
        return [feature] + offered.filter { $0 != feature }
    }

    @ViewBuilder
    private var purchaseRow: some View {
        if store.isUnlocked {
            Label("Pro is unlocked. Thank you for supporting MindMap AI.", systemImage: "checkmark.seal")
                .accessibilityIdentifier(AccessibilityID.Paywall.unlocked)
        } else {
            switch store.productState {
            case .loading:
                ProgressView("Loading price…")
            case .unavailable:
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Can’t reach the App Store. Check your connection and try again.")
                        .foregroundStyle(.secondary)
                    Button("Try Again") {
                        Task { await store.loadProduct() }
                    }
                }
            case .loaded(let product):
                Button {
                    Task { await store.purchase { try await purchase($0) } }
                } label: {
                    Text("Unlock Pro for \(product.displayPrice)")
                        .frame(maxWidth: .infinity, minHeight: Metrics.minimumHitTarget)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.purchaseState == .purchasing)
                .accessibilityIdentifier(AccessibilityID.Paywall.purchase)

                switch store.purchaseState {
                case .pending:
                    Text("Your purchase is waiting for approval. Pro unlocks as soon as it’s approved.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(AccessibilityID.Paywall.purchaseStatus)
                case .failed:
                    Text("The purchase didn’t go through. Try again.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(AccessibilityID.Paywall.purchaseStatus)
                case .idle, .purchasing:
                    EmptyView()
                }
            }
        }
    }
}

/// Settings ▸ MindMap AI Pro: status, the paywall, Restore Purchases (App Review 3.1.1)
/// and Redeem Code for a Pro gift code.
struct ProSettingsSection: View {
    @Environment(ProEntitlement.self) private var store
    @State private var isShowingPaywall = false
    @State private var isRedeeming = false

    var body: some View {
        Section {
            LabeledContent("Status") {
                Text(store.isUnlocked ? String(localized: "Unlocked") : String(localized: "Not unlocked"))
                    .accessibilityIdentifier(AccessibilityID.Settings.proStatus)
            }
                // On the one row that is always there: a modifier on a Section
                // goes to each of its rows, and one paywall sheet per row on one
                // binding made iOS close Settings instead of showing it (MM-90).
                .redeemCodeSheet(isPresented: $isRedeeming)
                .sheet(isPresented: $isShowingPaywall) {
                    PaywallView()
                }
                // The paywall shows its own result while it is open; one alert at a time.
                .restoreResultAlert(store, isActive: !isShowingPaywall)
            if !store.isUnlocked {
                Button("See What’s in Pro…") { isShowingPaywall = true }
                    .accessibilityIdentifier(AccessibilityID.Settings.showPaywall)
            }
            Button("Restore Purchases") {
                Task { await store.restorePurchases() }
            }
            .disabled(store.restoreState == .restoring)
            .accessibilityIdentifier(AccessibilityID.Settings.restorePurchases)
            if !store.isUnlocked {
                Button("Redeem Code…") { isRedeeming = true }
            }
        } header: {
            Text("MindMap AI Pro")
        } footer: {
            Text("Bought Pro before, or on another device? Restore Purchases unlocks it here.")
        }
    }
}

private extension View {
    /// Tells the person how Restore Purchases went; StoreKit shows nothing by itself.
    func restoreResultAlert(_ store: ProEntitlement, isActive: Bool = true) -> some View {
        alert(
            restoreTitle(store.restoreState).map { Text($0) } ?? Text(verbatim: ""),
            isPresented: Binding(
                get: { isActive && restoreTitle(store.restoreState) != nil },
                set: { if !$0 { store.dismissRestoreResult() } }
            ),
            presenting: store.restoreState
        ) { _ in
            Button("OK") { store.dismissRestoreResult() }
        } message: { state in
            switch state {
            case .restored: Text("MindMap AI Pro is unlocked on this device.")
            case .nothingToRestore: Text("This Apple Account hasn’t bought MindMap AI Pro.")
            default: Text("Couldn’t reach the App Store. Check your connection and try again.")
            }
        }
    }
}

private func restoreTitle(_ state: ProEntitlement.RestoreState) -> LocalizedStringKey? {
    switch state {
    case .restored: "Purchases Restored"
    case .nothingToRestore: "Nothing to Restore"
    case .failed: "Couldn’t Restore Purchases"
    case .idle, .restoring: nil
    }
}

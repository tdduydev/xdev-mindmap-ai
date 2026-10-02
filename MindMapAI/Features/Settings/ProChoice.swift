import SwiftUI

/// A Settings choice that needs Pro, picked without it: the paywall opens, and
/// the choice is kept only if Pro is unlocked there.
struct PendingProChoice: Identifiable {
    let id = UUID()
    let feature: ProFeature
    let apply: () -> Void
}

/// A picker item; a star marks a choice that comes with Pro and is not unlocked.
struct ProChoiceLabel: View {
    let title: LocalizedStringResource
    let isLocked: Bool

    var body: some View {
        if isLocked {
            Label { Text(title) } icon: { Image(systemName: "star") }
                .accessibilityLabel(Text("\(Text(title)), MindMap AI Pro"))
        } else {
            Text(title)
        }
    }
}

extension View {
    func proChoicePaywall(_ pending: Binding<PendingProChoice?>) -> some View {
        modifier(ProChoicePaywall(pending: pending))
    }
}

private struct ProChoicePaywall: ViewModifier {
    @Binding var pending: PendingProChoice?
    @Environment(ProEntitlement.self) private var pro

    func body(content: Content) -> some View {
        content.sheet(item: $pending) { choice in
            PaywallView(feature: choice.feature)
                // The purchase may finish while the paywall is still open, or never.
                .onDisappear {
                    if pro.allows(choice.feature) { choice.apply() }
                }
        }
    }
}

import SwiftUI

/// A short introduction over the sample map. The map is usable as soon as this
/// sheet is dismissed, including when the person skips on the first page.
struct OnboardingView: View {
    let finish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0

    private let symbols = ["point.3.connected.trianglepath.dotted", "arrow.turn.down.right", "sparkles"]
    private let titles: [LocalizedStringKey] = [
        "Make Ideas Visible", "Grow Your Map", "Explore More",
    ]
    private let details: [LocalizedStringKey] = [
        "This sample map is yours to explore and edit.",
        "Select a topic, then add a child or sibling to build your ideas.",
        "Use Find to jump to a topic, or ask on-device AI for ideas and answers.",
    ]

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer(minLength: Spacing.lg)
            Image(systemName: symbols[page])
                .font(.largeTitle)
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
            Text(titles[page])
                .font(Typography.Content.display.font)
                .multilineTextAlignment(.center)
            Text(details[page])
                .font(Typography.rowDetail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: Spacing.lg)
            HStack(spacing: Spacing.sm) {
                Button("Skip", action: finish)
                    .accessibilityIdentifier(AccessibilityID.Onboarding.skip)
                Spacer()
                Text("\(page + 1) of 3")
                    .font(Typography.statusLine)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(AccessibilityID.Onboarding.progress)
                Spacer()
                Button(page == 2 ? "Start Exploring" : "Next") {
                    if page == 2 {
                        finish()
                    } else {
                        withAnimation(Motion.standard(reduceMotion: reduceMotion)) { page += 1 }
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(AccessibilityID.Onboarding.next)
            }
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: Metrics.onboardingWidth, minHeight: Metrics.onboardingHeight)
        .interactiveDismissDisabled()
        .accessibilityIdentifier(AccessibilityID.Onboarding.sheet)
    }
}

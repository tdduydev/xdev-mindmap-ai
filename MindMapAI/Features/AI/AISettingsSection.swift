import SwiftUI

/// FR-SET-05: whether AI can run here and, if not, what to do about it.
/// Hidden on devices that can never run Apple Intelligence, like every other
/// AI entry point.
struct AISettingsSection: View {
    @Environment(AIService.self) private var ai

    var body: some View {
        if ai.showsEntryPoints {
            Section {
                LabeledContent("Apple Intelligence", value: AIAvailabilityText.status(for: ai.modelState))
            } header: {
                Text("AI")
            } footer: {
                if let explanation = AIAvailabilityText.explanation(for: ai.modelState) {
                    Text(explanation)
                } else {
                    Text("AI runs on this device. Your maps and requests are never sent to xDev.")
                }
            }
            .task { await ai.refresh() }
        }
    }
}

import MindMapAICore
import MindMapCapture
import SwiftUI

/// Settings ▸ AI (FR-SET-05): whether AI can run here and what to do if not,
/// the switch that takes AI out of the app, and the voice input language.
/// Hidden on devices that can never run Apple Intelligence, like every other
/// AI entry point; voice then moves to General, since it uses Speech, not the model.
struct AISettingsSection: View {
    @Environment(AIService.self) private var ai
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var ai = ai
        if ai.showsEntryPoints {
            Section {
                LabeledContent("Apple Intelligence", value: AIAvailabilityText.status(for: ai.modelState))
                    .accessibilityIdentifier(AccessibilityID.Settings.aiStatus)
                #if os(macOS)
                // iPad and iPhone have no public link to that page, so their
                // footer gives the path instead (docs/settings.md).
                if ai.modelState == .appleIntelligenceOff {
                    Button("Open Apple Intelligence Settings…") { openURL(AppLinks.appleIntelligenceSettings) }
                }
                #endif
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
            Section {
                Toggle("Use AI Features", isOn: $ai.isEnabled)
                    .accessibilityIdentifier(AccessibilityID.Settings.useAI)
            } footer: {
                Text("When off, AI actions are removed from maps and the AI menu is unavailable. Suggestions already on a map stay until you accept or discard them.")
            }
            VoiceInputSettingsSection()
        }
    }
}

/// The language Add Topics by Voice listens in. The voice sheet has its own
/// picker on the same key, so the choice can also be made where it is used.
struct VoiceInputSettingsSection: View {
    @AppStorage(VoiceInput.languageKey, store: AppDefaults.store) private var storedLanguage: VoiceLanguage?
    @Environment(ProEntitlement.self) private var pro

    var body: some View {
        Section {
            Picker("Voice Input Language", selection: Binding(
                get: { storedLanguage ?? VoiceLanguage.preferred() },
                set: { storedLanguage = $0 }
            )) {
                ForEach(VoiceLanguage.allCases, id: \.self) { language in
                    Text(language.title).tag(language)
                }
            }
            .accessibilityIdentifier(AccessibilityID.Settings.voiceInputLanguage)
        } header: {
            Text("Voice Input")
        } footer: {
            // Visible to everyone, so the language is right the moment Pro unlocks.
            if pro.allows(.voiceInput) {
                Text("Add Topics by Voice listens in this language. Speech is turned into text on this device.")
            } else {
                Text("Voice input is part of MindMap AI Pro.")
            }
        }
    }
}

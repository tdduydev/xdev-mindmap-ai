import MindMapCapture
import SwiftUI

/// Add Topics by Voice: listen, review the topics heard, then add them in one
/// step. Nothing touches the map before Add Topics.
struct VoiceInputSheet: View {
    @Bindable var voice: VoiceInput

    var body: some View {
        NavigationStack {
            Form {
                if voice.phase == .locked {
                    Section {
                        Label("Voice input is part of MindMap AI Pro.", systemImage: "lock")
                    }
                } else {
                    listeningSection
                    topicsSection
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text("Add Topics by Voice"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: voice.close)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Topics", action: voice.addTopics)
                        .disabled(!voice.canAddTopics)
                        .accessibilityIdentifier(AccessibilityID.Voice.addTopics)
                }
            }
        }
        #if os(macOS)
        .frame(width: Metrics.aiSheetWidth)
        #endif
    }

    private var listeningSection: some View {
        Section {
            Picker("Language", selection: $voice.language) {
                ForEach(VoiceLanguage.allCases, id: \.self) { language in
                    Text(language.title).tag(language)
                }
            }
            .disabled(!voice.canChangeLanguage)
            status
            if !voice.transcript.pending.isEmpty {
                Text(verbatim: voice.transcript.pending)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("Hearing: \(voice.transcript.pending)"))
            }
        } footer: {
            Text("Say one topic per sentence. Speech is turned into text on this device and is not sent to xDev.")
        }
    }

    @ViewBuilder
    private var status: some View {
        switch voice.phase {
        case .idle, .locked:
            Button(action: voice.startListening) {
                Label("Start Listening", systemImage: "mic")
            }
            .accessibilityIdentifier(AccessibilityID.Voice.listen)
        case .preparing:
            Label {
                Text("Getting ready…")
            } icon: {
                ProgressView().controlSize(.small)
            }
        case .needsDownload:
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Voice input needs the \(Text(voice.language.title)) speech model, which the system downloads once.")
                Button("Download Speech Model", action: voice.download)
            }
        case .downloading(let fraction):
            ProgressView(value: fraction) {
                Text("Downloading speech model…")
            }
        case .listening:
            Button(action: voice.stopListening) {
                Label("Stop Listening", systemImage: "mic.fill")
            }
            .accessibilityIdentifier(AccessibilityID.Voice.listen)
            .accessibilityHint(Text("Listening"))
        case .finishing:
            Label {
                Text("Finishing…")
            } icon: {
                ProgressView().controlSize(.small)
            }
        case .failed(let failure):
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label(failure.message, systemImage: "exclamationmark.circle")
                Button("Try Again", action: voice.startListening)
            }
        }
    }

    private var topicsSection: some View {
        Section {
            if voice.transcript.topics.isEmpty {
                Text("Topics you say appear here. You can edit them before adding.")
                    .foregroundStyle(.secondary)
            }
            ForEach($voice.transcript.topics) { $topic in
                HStack {
                    TextField("Topic", text: $topic.title)
                    Button {
                        voice.removeTopic(topic.id)
                    } label: {
                        Label("Remove", systemImage: "minus.circle")
                            .labelStyle(.iconOnly)
                            .frame(minWidth: Metrics.minimumHitTarget, minHeight: Metrics.minimumHitTarget)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .onDelete(perform: voice.removeTopics(at:))
        } header: {
            Text("Topics")
        }
    }
}

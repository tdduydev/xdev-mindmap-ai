import SwiftUI

/// FR-WCH-01: one field. Tapping it offers dictation, Scribble and the
/// keyboard; Done saves the idea as a topic in the Inbox map.
struct CaptureView: View {
    let model: WatchModel
    @State private var idea = ""
    @State private var result: WatchModel.CaptureResult?
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            switch result {
            case .added:
                Label("Added to Inbox", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("watch.added")
            case .failed:
                Text("The idea couldn't be saved. Try again.")
                    .foregroundStyle(.secondary)
            case nil:
                EmptyView()
            }
            if result != .added {
                TextField("Idea", text: $idea)
                    .submitLabel(.done)
                    .onSubmit(save)
                    .disabled(isSaving)
                    .accessibilityIdentifier("watch.ideaField")
                Button("Add to Inbox", action: save)
                    .disabled(isSaving || idea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("watch.save")
            }
        }
        .navigationTitle("New Idea")
        .task(id: result) {
            // Long enough to read the confirmation, then back to the list.
            guard result == .added else { return }
            try? await Task.sleep(for: WatchStyle.confirmationDuration)
            dismiss()
        }
    }

    private func save() {
        guard !isSaving, !idea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSaving = true
        Task {
            result = await model.addIdea(idea)
            isSaving = false
        }
    }
}

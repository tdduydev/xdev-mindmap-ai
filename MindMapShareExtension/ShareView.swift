import MindMapDomain
import SwiftUI

/// Standard form controls only: the extension does not link the app's design
/// system, and the share sheet should look like the system's own.
struct ShareView: View {
    @Bindable var model: ShareModel
    /// `true` once the share was saved, `false` on Cancel.
    let onDone: (Bool) -> Void

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("MindMap AI")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { onDone(false) }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task { if await model.save() { onDone(true) } }
                        }
                        .disabled(!model.canSave)
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: ShareMetrics.minimumWidth, minHeight: ShareMetrics.minimumHeight)
        #endif
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading, .saving:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .needsApp:
            ContentUnavailableView(
                "Open MindMap AI First",
                systemImage: "app.badge",
                description: Text("Open the app once so it can set up your maps, then share again.")
            )
        case .failed:
            ContentUnavailableView(
                "Can’t Save to MindMap AI",
                systemImage: "exclamationmark.triangle",
                description: Text("Your maps couldn’t be opened. Open MindMap AI and try again.")
            )
        case .ready:
            form
        }
    }

    private var form: some View {
        Form {
            Section("Shared") {
                if model.topics.isEmpty && model.fileCount == 0 {
                    Text("Nothing here can be added to a map.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(model.topics.enumerated()), id: \.offset) { _, title in
                    Text(title)
                        .lineLimit(2)
                }
                if model.fileCount > 0 {
                    Text("\(model.fileCount) images and PDFs will be kept with the map for MindMap AI to read later.")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Picker("Add To", selection: $model.destination) {
                    Text("New Mind Map").tag(ShareModel.Destination.newMap)
                    ForEach(model.recentMaps) { map in
                        Text(map.title).tag(ShareModel.Destination.existing(map.id))
                    }
                }
                if model.destination == .newMap {
                    TextField("Title", text: $model.newMapTitle, prompt: Text("Untitled Map"))
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// The macOS share popover's size; iOS sizes the sheet itself.
enum ShareMetrics {
    static let minimumWidth: CGFloat = 380
    static let minimumHeight: CGFloat = 340
}

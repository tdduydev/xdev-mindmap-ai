import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let showRecentlyDeleted = Notification.Name("asia.xdev.mindmapai.showRecentlyDeleted")
}

struct DataSettingsSection: View {
    @State private var model: DataSettingsModel
    @State private var confirmsEmpty = false
    let showRecentlyDeleted: (() -> Void)?

    init(environment: AppEnvironment, showRecentlyDeleted: (() -> Void)?) {
        _model = State(initialValue: DataSettingsModel(
            repository: environment.repository, spotlightIndex: environment.spotlightIndex
        ))
        self.showRecentlyDeleted = showRecentlyDeleted
    }

    var body: some View {
        Section {
            LabeledContent("Recently Deleted", value: String(localized: "\(model.deletedCount) maps"))
                // On the one row that is always there: a modifier on a Section
                // goes to each of its rows, so each row would observe and present
                // its own copy on one binding (MM-90, MM-92).
                .task { await model.observe() }
                .confirmationDialog(
                    "Delete \(model.deletedCount) maps permanently?",
                    isPresented: $confirmsEmpty,
                    titleVisibility: .visible
                ) {
                    Button("Delete Permanently") { Task { await model.emptyRecentlyDeleted() } }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This can’t be undone.")
                }
                .fileExporter(
                    isPresented: Binding(get: { model.exportFolder != nil }, set: { if !$0 { model.exportFolder = nil } }),
                    document: model.exportFolder,
                    contentType: .folder,
                    defaultFilename: String(localized: "MindMap AI Backups")
                ) { result in
                    if case .failure = result { model.failure = String(localized: "Couldn’t save the backup folder.") }
                    model.exportFolder = nil
                }
                .fileImporter(
                    isPresented: $model.isImporting,
                    allowedContentTypes: [.markdownText, .plainText, .text, .json],
                    allowsMultipleSelection: true
                ) { result in
                    Task { await model.importFiles(result) }
                }
                .alert(
                    "Something Went Wrong",
                    isPresented: Binding(get: { model.failure != nil }, set: { if !$0 { model.failure = nil } })
                ) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(model.failure ?? "")
                }
            Button("Show in Library") { showRecentlyDeleted?() }
                .disabled(showRecentlyDeleted == nil)
            Button("Empty Recently Deleted…") { confirmsEmpty = true }
                .disabled(model.deletedCount == 0 || model.isBusy)
                .accessibilityIdentifier(AccessibilityID.Settings.emptyRecentlyDeleted)
        } footer: {
            Text("Deleted maps stay for 30 days before they’re removed permanently.")
        }
        Section {
            Button("Export All Maps…") { Task { await model.prepareExport() } }
                .disabled(model.isBusy)
                .accessibilityIdentifier(AccessibilityID.Settings.exportAllMaps)
            Button("Import Maps…") { model.isImporting = true }
                .disabled(model.isBusy)
            if model.isBusy, model.exportTotal > 0 {
                ProgressView(value: Double(model.exportProgress), total: Double(model.exportTotal))
                    .accessibilityLabel("Preparing backup")
            }
        } footer: {
            Text("Export writes one MindMap AI Backup file for each map. Import creates new maps and keeps existing maps.")
        }
    }
}

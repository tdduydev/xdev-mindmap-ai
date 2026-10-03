import SwiftUI

extension FocusedValues {
    /// The frontmost window's import and export.
    @Entry var fileTransfer: FileTransfer?
}

/// File ▸ Import… and Export… (FR-IO-08), in the menu's import/export group.
struct FileTransferCommands: Commands {
    @FocusedValue(\.fileTransfer) private var transfer
    @FocusedValue(\.editorSession) private var editor

    var body: some Commands {
        CommandGroup(replacing: .importExport) {
            Button("Import…") { transfer?.beginImport(.newMap) }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(transfer == nil)
            Button("Import into Map…") {
                if let editor { transfer?.beginImport(.openMap(editor)) }
            }
            .keyboardShortcut("i", modifiers: [.command, .shift, .option])
            .disabled(transfer == nil || editor == nil)
            Divider()
            Button("Export…") {
                if let editor { transfer?.beginExport(editor) }
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(transfer == nil || editor == nil)
        }
    }
}

/// The open panel, the export sheet and the import alert of one window.
struct FileTransferPresenter: ViewModifier {
    @Bindable var transfer: FileTransfer
    /// Until MM-13's StoreKit entitlement reaches main, the hook AI uses.
    let entitlements: any ProEntitlements

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $transfer.isImporting, allowedContentTypes: MapImporter.contentTypes) { result in
                Task { await transfer.finishImport(result) }
            }
            .sheet(item: $transfer.exportRequest) { request in
                ExportSheet(session: request.session, entitlements: entitlements) {
                    transfer.exportRequest = nil
                }
            }
            .alert(
                transfer.failure?.title ?? "",
                isPresented: Binding(get: { transfer.failure != nil }, set: { if !$0 { transfer.failure = nil } }),
                presenting: transfer.failure
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { failure in
                Text(failure.message)
            }
            .alert(
                transfer.importSummary?.title ?? "",
                isPresented: Binding(get: { transfer.importSummary != nil }, set: { if !$0 { transfer.importSummary = nil } }),
                presenting: transfer.importSummary
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { summary in
                Text(summary.message)
            }
            .overlay(alignment: .bottom) {
                if let files = UITestFiles.shared { UITestExportReport(files: files) }
            }
            .environment(transfer)
            .focusedSceneValue(\.fileTransfer, transfer)
    }
}

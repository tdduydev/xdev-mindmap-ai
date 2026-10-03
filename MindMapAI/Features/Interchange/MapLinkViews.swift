import MindMapInterchange
import SwiftUI

/// File ▸ Share Link… and Open Map Link… (FR-CLP-01, FR-CLP-02), after Import and Export.
struct MapLinkCommands: Commands {
    @FocusedValue(\.fileTransfer) private var transfer
    @FocusedValue(\.editorSession) private var editor

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Share Link…") {
                if let editor { transfer?.beginShareLink(editor) }
            }
            // [Đề xuất] ⌥⌘S: the app has no Save As or Save All to clash with.
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(transfer == nil || editor == nil)
            Button("Open Map Link…") { transfer?.isOpeningMapLink = true }
                .disabled(transfer == nil)
        }
    }
}

/// The Share Link and Open Map Link sheets of one window, their alert, and
/// map links the system hands the app (universal links).
struct MapLinkPresenter: ViewModifier {
    @Bindable var transfer: FileTransfer

    func body(content: Content) -> some View {
        content
            .sheet(item: $transfer.shareLinkRequest) { request in
                ShareLinkSheet(model: ShareLinkModel(session: request.session)) {
                    transfer.shareLinkRequest = nil
                    transfer.beginExport(request.session)
                }
            }
            .sheet(isPresented: $transfer.isOpeningMapLink) {
                OpenMapLinkSheet(transfer: transfer)
            }
            .alert(
                transfer.mapLinkFailure?.title ?? "",
                // While the Open Map Link sheet is up, it shows the failure itself.
                isPresented: Binding(
                    get: { transfer.mapLinkFailure != nil && !transfer.isOpeningMapLink },
                    set: { if !$0 { transfer.mapLinkFailure = nil } }
                ),
                presenting: transfer.mapLinkFailure
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { failure in
                Text(failure.message)
            }
            // SwiftUI hands a universal link to onOpenURL; the activity is
            // Apple's documented path too. Both go to one method, which drops
            // a second delivery of the same link.
            .onOpenURL { url in
                guard FileTransfer.isMapLink(url) else { return }
                Task { await transfer.openMapLink(url) }
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                guard let url = activity.webpageURL, FileTransfer.isMapLink(url) else { return }
                Task { await transfer.openMapLink(url) }
            }
    }
}

/// Share Link…: the link of the map or of the selected branch, or, when it
/// is too long, the smaller shares that fit. Nothing is cut (docs/app-clip.md).
struct ShareLinkSheet: View {
    @State var model: ShareLinkModel
    let export: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                if let branchID = model.branchID {
                    Picker("Share", selection: $model.scope) {
                        Text("Share Map").tag(ShareLinkModel.Scope.map)
                        Text("Share Branch").tag(ShareLinkModel.Scope.branch(branchID))
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                content
            }
            .formStyle(.grouped)
            .navigationTitle(Text("Share Link"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: model.scope) {
            copied = false
            await model.prepare()
        }
        #if os(macOS)
        .frame(minWidth: Metrics.shareLinkSheetMinWidth, minHeight: Metrics.shareLinkSheetMinHeight)
        #endif
    }

    @ViewBuilder
    private var content: some View {
        switch model.status {
        case .preparing:
            ProgressView("Preparing Link…")
                .frame(maxWidth: .infinity)
        case .ready(let url, let withoutNotes):
            Section {
                ShareLink(item: url, subject: Text(model.title))
                Button(copied ? LocalizedStringKey("Link Copied") : "Copy Link", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    Clipboard.copy(url.absoluteString)
                    copied = true
                }
            } footer: {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Anyone with this link can see the map.")
                    Text("Images, tags and connections aren’t included in links.")
                    if withoutNotes { Text("Notes aren’t included.") }
                }
            }
        case .tooLong(let canShareWithoutNotes):
            Section {
                Text(model.scope == .map ? LocalizedStringKey("This map is too big for a link.") : "This branch is too big for a link.")
                if canShareWithoutNotes {
                    Button("Share Without Notes", action: model.shareWithoutNotes)
                }
                if let branchID = model.branchToOffer {
                    Button("Share Branch") { model.scope = .branch(branchID) }
                }
                Button("Export…") {
                    dismiss()
                    export()
                }
            } footer: {
                if model.branchID == nil {
                    Text("Select a topic to share its branch instead.")
                }
            }
        }
    }
}

/// File ▸ Open Map Link…: for a link pasted from a browser or another screen.
struct OpenMapLinkSheet: View {
    let transfer: FileTransfer
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isOpening = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Map Link", text: $text, prompt: Text(verbatim: "https://\(MapLinkCodec.host)\(MapLinkCodec.path)#…"))
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .onSubmit(open)
                        .onChange(of: text) { transfer.mapLinkFailure = nil }
                } footer: {
                    if let failure = transfer.mapLinkFailure {
                        Text(failure.message)
                            .foregroundStyle(Palette.danger)
                    } else {
                        Text("Paste a map link from MindMap AI. It opens as a new map.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text("Open Map Link"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open", action: open)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isOpening)
                }
            }
        }
        .onDisappear { transfer.mapLinkFailure = nil }
        #if os(macOS)
        .frame(minWidth: Metrics.openMapLinkSheetMinWidth)
        #endif
    }

    private func open() {
        isOpening = true
        Task {
            await transfer.openMapLink(text: text)
            isOpening = false
        }
    }
}

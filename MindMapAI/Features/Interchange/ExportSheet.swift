import Foundation
import OSLog
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import SwiftUI

/// File ▸ Export…: the format and its options, then the save panel. The file
/// is made before the panel opens, so a failure shows here, not after the
/// user has picked a place.
struct ExportSheet: View {
    let session: EditorSession
    let entitlements: any ProEntitlements
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    /// Starts from Settings ▸ Export; a change here becomes the new default there.
    @State private var options: ExportOptions
    @State private var scope = ExportScope.wholeMap
    @State private var file: ExportedFile?
    @State private var isPreparing = false
    @State private var failed = false

    init(session: EditorSession, entitlements: any ProEntitlements, onClose: @escaping () -> Void) {
        self.session = session
        self.entitlements = entitlements
        self.onClose = onClose
        _options = State(initialValue: ExportPreferences().options(entitlements: entitlements))
    }

    private var lockedFeature: ProFeature? {
        options.requiredFeature.flatMap { entitlements.allows($0) ? nil : $0 }
    }

    /// The root is the whole map, so only a topic below it makes a branch.
    private var selectedBranch: NodeID? {
        session.selection.flatMap { $0 == session.rootID ? nil : $0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Format", selection: $options.format) {
                        ForEach(ExportFormat.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    .accessibilityIdentifier(AccessibilityID.Export.format)
                }
                switch options.format {
                case .markdown, .plainText:
                    textOptions
                case .png:
                    imageOptions
                case .pdf:
                    pdfOptions
                case .backup:
                    Section {} footer: {
                        Text("The whole map with its theme, colors, symbols, tasks, tags, connections and boundaries. Import it again with File ▸ Import….")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Export Map")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onClose)
                        .accessibilityIdentifier(AccessibilityID.Export.cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export…", action: prepare)
                        .disabled(isPreparing || lockedFeature != nil)
                        .accessibilityIdentifier(AccessibilityID.Export.export)
                }
            }
        }
        #if os(macOS)
        .frame(width: Metrics.exportSheetWidth)
        #endif
        .fileExporter(
            isPresented: Binding(get: { file != nil }, set: { if !$0 { file = nil } }),
            document: file,
            contentType: options.format.contentType,
            defaultFilename: MapExporter.fileName(for: session.map.title)
        ) { result in
            file = nil
            switch result {
            case .success:
                onClose()
            case .failure(let error):
                Log.interchange.error("Saving an export failed: \(error.localizedDescription, privacy: .private)")
                failed = true
            }
        }
        .onChange(of: options) { old, new in
            ExportPreferences().save(new, changedFrom: old)
        }
        .alert("Couldn’t Export Map", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The file couldn’t be made or saved. Try again, or choose another folder.")
        }
    }

    @ViewBuilder
    private var textOptions: some View {
        Section {
            Picker("Include", selection: $scope) {
                Text("Whole Map").tag(ExportScope.wholeMap)
                Text("Selected Branch").tag(ExportScope.selectedBranch)
                    .selectionDisabled(selectedBranch == nil)
            }
            Toggle("Include Notes", isOn: $options.includeNotes)
        } footer: {
            Text("Markdown and plain text open in any text editor and can be imported again.")
        }
    }

    @ViewBuilder
    private var imageOptions: some View {
        Section {
            Picker("Resolution", selection: $options.imageScale) {
                ForEach(ImageScale.allCases) { scale in
                    Text(scale.title).tag(scale)
                }
            }
            backgroundPicker
        } footer: {
            footer(default: Text("The whole map, collapsed branches as they are on the canvas."))
        }
    }

    @ViewBuilder
    private var pdfOptions: some View {
        Section {
            Picker("Pages", selection: $options.pageMode) {
                ForEach(PDFPageMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            Picker("Paper Size", selection: $options.paper) {
                ForEach(PaperSize.allCases) { paper in
                    Text(paper.title).tag(paper)
                }
            }
            backgroundPicker
        } footer: {
            footer(default: Text("Text and lines stay sharp at any zoom, and the text can be searched."))
        }
    }

    private var backgroundPicker: some View {
        Picker("Background", selection: $options.background) {
            ForEach(ExportBackground.allCases) { background in
                Text(background.title).tag(background)
            }
        }
    }

    private func footer(default text: Text) -> Text {
        lockedFeature == nil ? text : Text("This option comes with MindMap AI Pro.")
    }

    private func prepare() {
        var options = options
        options.branch = scope == .selectedBranch ? selectedBranch : nil
        let graph = session.engine.state
        let repository = session.repository
        isPreparing = true
        Task {
            defer { isPreparing = false }
            do {
                await session.flush()
                let imageData = [ExportFormat.backup, .png, .pdf].contains(options.format)
                    ? try await repository.imageData(of: graph) : [:]
                file = ExportedFile(data: try await MapExporter.data(for: graph, options: options, colorScheme: colorScheme, imageData: imageData))
            } catch {
                Log.interchange.error("Making an export failed: \(String(describing: error), privacy: .private)")
                failed = true
            }
        }
    }
}

/// What a text export covers.
enum ExportScope: Hashable {
    case wholeMap
    /// The selected topic and everything under it (FR-IO-03).
    case selectedBranch
}

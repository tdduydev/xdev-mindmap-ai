import Foundation
import MindMapDomain
import MindMapGraph
import MindMapInterchange
import Observation
import OSLog

/// File ▸ Import… and Export… for one window: which panel is up, where an
/// import goes, and what went wrong. The root view presents the panels; the
/// work is done here and in `MapImporter`/`MapExporter`, not in views.
@Observable
final class FileTransfer {
    enum ImportDestination {
        /// A new map in the library (FR-IO-07).
        case newMap
        /// Under the selected topic of an open map, as one undo step.
        case openMap(EditorSession)
    }

    struct ExportRequest: Identifiable {
        let id = UUID()
        let session: EditorSession
    }

    /// Drives `fileImporter`.
    var isImporting = false
    /// Drives the export sheet.
    var exportRequest: ExportRequest?
    /// Shown as an alert.
    var failure: ImportFailure?

    /// Kept apart from `isImporting`, which the panel clears before it reports the file.
    @ObservationIgnored private var pendingDestination: ImportDestination?
    @ObservationIgnored private let createMap: (GraphState) async -> MapID?
    @ObservationIgnored private let openMap: (MapID) -> Void

    /// - Parameters:
    ///   - createMap: Stores a new map and returns its ID, or nil when saving failed.
    ///   - openMap: Shows a map in the window.
    init(createMap: @escaping (GraphState) async -> MapID?, openMap: @escaping (MapID) -> Void) {
        self.createMap = createMap
        self.openMap = openMap
    }

    func beginImport(_ destination: ImportDestination) {
        pendingDestination = destination
        isImporting = true
    }

    func beginExport(_ session: EditorSession) {
        exportRequest = ExportRequest(session: session)
    }

    /// The open panel's answer.
    func finishImport(_ result: Result<URL, any Error>) async {
        guard let destination = pendingDestination else { return }
        pendingDestination = nil
        switch result {
        case .success(let url):
            await importFile(at: url, into: destination)
        case .failure(let error):
            Log.interchange.error("The open panel failed: \(error.localizedDescription, privacy: .private)")
            failure = .couldNotRead(fileName: "")
        }
    }

    func importFile(at url: URL, into destination: ImportDestination) async {
        let file: ImportedFile
        do {
            file = try await MapImporter.read(url)
        } catch {
            failure = error
            return
        }

        switch destination {
        case .newMap:
            guard let graph = try? GraphState.imported(from: file.draft, title: file.name) else {
                failure = .emptyDocument(fileName: url.lastPathComponent)
                return
            }
            guard let id = await createMap(graph) else {
                failure = .couldNotSave
                return
            }
            openMap(id)
        case .openMap(let session):
            if !session.importOutline(file.draft) { failure = .couldNotSave }
        }
    }
}

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
    /// What a file from another app had that the new map could not keep,
    /// shown after the map opens (FR-IO-13). Nil when nothing was lost.
    var importSummary: ImportSummary?
    /// Drives the Share Link sheet (MM-113, `FileTransfer+MapLinks.swift`).
    var shareLinkRequest: ShareLinkRequest?
    /// Drives the Open Map Link sheet.
    var isOpeningMapLink = false
    /// A map link that could not be opened, shown as an alert (FR-IO-09).
    var mapLinkFailure: MapLinkFailure?
    /// The last link opened, so a universal link the system delivers twice opens one map.
    @ObservationIgnored var lastOpenedLink: (url: URL, date: Date)?

    /// Kept apart from `isImporting`, which the panel clears before it reports the file.
    @ObservationIgnored private var pendingDestination: ImportDestination?
    @ObservationIgnored let createMap: (GraphState, [ImageID: Data]) async -> MapID?
    @ObservationIgnored let openMap: (MapID) -> Void

    /// - Parameters:
    ///   - createMap: Stores a new map with the bytes of its images and
    ///     returns its ID, or nil when saving failed.
    ///   - openMap: Shows a map in the window.
    init(createMap: @escaping (GraphState, [ImageID: Data]) async -> MapID?, openMap: @escaping (MapID) -> Void) {
        self.createMap = createMap
        self.openMap = openMap
    }

    func beginImport(_ destination: ImportDestination) {
        pendingDestination = destination
        if let files = UITestFiles.shared {
            // The UI test mode's stand-in for the open panel picks its fixture.
            Task { await finishImport(Result { try files.fixtureURL() }) }
            return
        }
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
            failure = .couldNotOpenPanel
        }
    }

    func importFile(at url: URL, into destination: ImportDestination) async {
        if MapImporter.isBackup(url) {
            await importBackup(at: url, into: destination)
            return
        }
        if let format = MapImporter.foreignFormat(of: url) {
            await importForeign(at: url, format: format, into: destination)
            return
        }
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
            guard let id = await createMap(graph, [:]) else {
                failure = .couldNotSave
                return
            }
            openMap(id)
        case .openMap(let session):
            guard session.importOutline(file.draft) else {
                failure = .couldNotSave
                return
            }
        }
        // Counts only: titles and file names are the user's content (docs/privacy.md).
        Log.interchange.info("Imported \(file.draft.items.count, privacy: .public) topics from \(file.format.rawValue, privacy: .public)")
    }

    /// Every map of the file is stored before the first opens, so a failure
    /// part way leaves no half-imported file behind the summary.
    private func importForeign(at url: URL, format: ForeignFormat, into destination: ImportDestination) async {
        guard case .newMap = destination else {
            failure = .foreignIntoMap(fileName: url.lastPathComponent)
            return
        }
        let imported: ForeignImport
        do {
            imported = try await MapImporter.readForeign(url, format: format)
        } catch {
            failure = error
            return
        }
        var created: [MapID] = []
        for map in imported.maps {
            let imageData = imported.imageData.filter { map.images[$0.key] != nil }
            guard let id = await createMap(map, imageData) else {
                failure = .couldNotSave
                return
            }
            created.append(id)
        }
        if let first = created.first { openMap(first) }
        if !imported.report.isEmpty {
            importSummary = ImportSummary(fileName: url.lastPathComponent, report: imported.report)
        }
        Log.interchange.info("Imported \(imported.maps.count, privacy: .public) maps from \(format.rawValue, privacy: .public), \(imported.report.entries.count, privacy: .public) kinds of loss")
    }

    private func importBackup(at url: URL, into destination: ImportDestination) async {
        guard case .newMap = destination else {
            failure = .backupIntoMap(fileName: url.lastPathComponent)
            return
        }
        let archive: MapArchive
        do {
            archive = try await MapImporter.readBackup(url)
        } catch {
            failure = error
            return
        }
        // Shared tags of the file become tags of the new map: the library's
        // shared tags are not loaded here (docs/interchange.md).
        let (graph, imageData) = archive.imported()
        guard let id = await createMap(graph, imageData) else {
            failure = .couldNotSave
            return
        }
        openMap(id)
        Log.interchange.info("Imported a backup of \(graph.nodes.count, privacy: .public) topics, version \(archive.version, privacy: .public)")
    }
}

/// The alert after an import from another app that could not keep everything.
struct ImportSummary: Identifiable, Equatable {
    let id = UUID()
    let fileName: String
    let report: ImportReport

    var title: String {
        String(localized: "Imported “\(fileName)”")
    }

    /// One line per kind of loss; every topic is in the map either way.
    var message: String {
        let lines = report.entries.map { Self.line(for: $0) }
        return (lines + [String(localized: "Every topic was imported.")]).joined(separator: "\n")
    }

    static func line(for entry: ImportReport.Entry) -> String {
        switch entry.loss {
        case .includedOutline:
            String(localized: "\(entry.count) linked outlines weren’t downloaded. Their links are on the topics.")
        case .image:
            String(localized: "\(entry.count) images couldn’t be imported.")
        case .attachment:
            String(localized: "\(entry.count) attached files couldn’t be imported.")
        case .icon:
            String(localized: "\(entry.count) icons couldn’t be imported.")
        case .connection:
            String(localized: "\(entry.count) relationships couldn’t be imported as connections.")
        case .summary:
            String(localized: "\(entry.count) summaries couldn’t be imported. Their topics are kept as subtopics.")
        case .boundary:
            String(localized: "\(entry.count) boundaries couldn’t be imported.")
        }
    }
}

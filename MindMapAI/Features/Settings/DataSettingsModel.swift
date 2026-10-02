import Foundation
import MindMapDomain
import MindMapGraph
import MindMapInterchange
import MindMapIntents
import MindMapPersistence
import Observation
import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// Data actions belong to Settings, but use the same repository and archive
/// reader as the library. A separate model also serves the Mac Settings scene.
@Observable
final class DataSettingsModel {
    private(set) var deletedCount = 0
    private(set) var isBusy = false
    private(set) var exportProgress = 0
    private(set) var exportTotal = 0
    var exportFolder: BackupFolder?
    var isImporting = false
    var failure: String?

    @ObservationIgnored private let repository: any MapRepository
    @ObservationIgnored private let spotlightIndex: any MapSearchIndex

    init(repository: any MapRepository, spotlightIndex: any MapSearchIndex) {
        self.repository = repository
        self.spotlightIndex = spotlightIndex
    }

    func refresh() async {
        do { deletedCount = try await repository.fetchDeletedMaps().count }
        catch { failure = String(localized: "Couldn’t load your maps.") }
    }

    func observe() async {
        let changes = await repository.changes()
        await refresh()
        for await change in changes {
            if Task.isCancelled { break }
            switch change {
            case .saved, .deleted, .storeChanged: await refresh()
            case .tagsChanged: break
            }
        }
    }

    func emptyRecentlyDeleted() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            // The user explicitly chose Empty, so every deleted map is due now.
            let ids = try await repository.purgeDeletedMaps(deletedBefore: .distantFuture)
            for id in ids { await spotlightIndex.remove(id) }
            await refresh()
        } catch {
            Log.persistence.error("Emptying Recently Deleted failed: \(String(describing: error), privacy: .private)")
            failure = String(localized: "Couldn’t delete the maps.")
        }
    }

    func prepareExport() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let maps = try await repository.fetchMaps()
            exportTotal = maps.count
            exportProgress = 0
            var files: [String: Data] = [:]
            for map in maps {
                guard let graph = try await repository.loadGraph(for: map.id) else { continue }
                let imageData = try await repository.imageData(of: graph)
                let data = try await MapArchive.exportData(graph, imageData: imageData)
                // An ID suffix makes equal titles safe in a single folder.
                let name = "\(MapExporter.fileName(for: map.title))-\(map.id).json"
                files[name] = data
                exportProgress += 1
            }
            exportFolder = BackupFolder(files: files)
        } catch {
            Log.interchange.error("Making the library backup failed: \(String(describing: error), privacy: .private)")
            failure = String(localized: "Couldn’t export your maps.")
        }
    }

    func importFiles(_ result: Result<[URL], any Error>) async {
        guard !isBusy else { return }
        guard case .success(let urls) = result else {
            failure = String(localized: "The files couldn’t be opened.")
            return
        }
        isBusy = true
        defer { isBusy = false }
        let transfer = FileTransfer(createMap: { [repository, spotlightIndex] graph, images in
            do {
                try await repository.create(graph, imageData: images)
                await spotlightIndex.update(graph.map)
                return graph.map.id
            } catch { return nil }
        }, openMap: { _ in })
        for url in urls {
            await transfer.importFile(at: url, into: .newMap)
            if let error = transfer.failure {
                failure = "\(error.title): \(error.message)"
                break
            }
        }
    }
}

/// A directory FileDocument lets the save panel choose where the complete
/// backup goes, without writing map data to a temporary location first.
nonisolated struct BackupFolder: FileDocument {
    static let readableContentTypes: [UTType] = []
    static let writableContentTypes: [UTType] = [.folder]

    let files: [String: Data]

    init(files: [String: Data]) { self.files = files }
    init(configuration: ReadConfiguration) throws { throw CocoaError(.featureUnsupported) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(directoryWithFileWrappers: files.mapValues { FileWrapper(regularFileWithContents: $0) })
    }
}

import Foundation
import MindMapDomain
import MindMapGraph

/// A file format made by another app that File ▸ Import… reads into new maps
/// (FR-IO-13). OPML comes first (MM-101); FreeMind, XMind and MindNode
/// (MM-102..104) add a case each, with a reader that fills a `ForeignImport`.
public enum ForeignFormat: String, Hashable, Sendable, CaseIterable {
    case opml
    /// XMind 8 and XMind 2020 and later (MM-103): a ZIP with one map per sheet.
    case xmind

    /// Nil for an extension no importer reads.
    public init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "opml": self = .opml
        case "xmind": self = .xmind
        default: return nil
        }
    }

    public var fileExtension: String {
        switch self {
        case .opml: "opml"
        case .xmind: "xmind"
        }
    }

    /// Reads the file into new maps. Runs off the caller's actor: a large
    /// outline takes a while and the window must stay responsive.
    ///
    /// - Parameter fileName: The file's name without its extension, the
    ///   central topic of a file with several top-level topics and no title.
    @concurrent
    public func read(_ data: Data, fileName: String, now: Date = .now) async throws(ForeignImportError) -> ForeignImport {
        switch self {
        case .opml:
            let document = try OPMLOutline.parse(data)
            let title = document.title.flatMap { $0.isEmpty ? nil : $0 } ?? fileName
            guard let map = try? GraphState.imported(from: document.draft, title: title, now: now) else {
                throw .emptyDocument
            }
            return ForeignImport(maps: [map], imageData: [:], report: document.report)
        case .xmind:
            return try XMindMap.read(data, fileName: fileName, now: now)
        }
    }
}

/// Maps read from a file made by another app, ready to be stored as new maps.
public struct ForeignImport: Sendable {
    /// One map per file, or one per sheet for formats that have several.
    public var maps: [GraphState]
    /// The bytes of the maps' images, for `MapRepository.create(_:imageData:)`.
    public var imageData: [ImageID: Data]
    /// What could not be carried over; empty when everything was.
    public var report: ImportReport

    public init(maps: [GraphState], imageData: [ImageID: Data] = [:], report: ImportReport = ImportReport()) {
        self.maps = maps
        self.imageData = imageData
        self.report = report
    }
}

/// Why a file from another app could not be read (FR-IO-09).
public enum ForeignImportError: Error, Hashable, Sendable {
    /// The file is not in the format its extension claims (an `.opml` file
    /// that is not an OPML document).
    case wrongFormat
    /// The file is in the format but broken: XML that does not parse, say.
    case damaged
    /// The file holds no topics.
    case emptyDocument
    /// An archive (XMind) whose contents would expand beyond what the app
    /// reads into memory, such as a zip bomb.
    case tooLarge
}

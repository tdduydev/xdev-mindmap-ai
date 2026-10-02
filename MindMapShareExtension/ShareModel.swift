import Foundation
import MindMapDomain
import MindMapInterchange
import MindMapPersistence
import MindMapSharing
import Observation
import OSLog
import UniformTypeIdentifiers

/// What the share sheet received and where it goes. Text and links become
/// topics now; images and PDFs wait in the App Group inbox for the app, which
/// can read them with OCR or AI later (FR-SYS-02). Nothing here loads a model.
@Observable
final class ShareModel {
    enum Destination: Hashable {
        case newMap
        case existing(MapID)
    }

    enum Phase: Equatable {
        case loading
        case ready
        case saving
        /// The app has not created the shared store yet, or has no App Group.
        case needsApp
        case failed
    }

    private(set) var phase = Phase.loading
    private(set) var topics: [String] = []
    private(set) var fileCount = 0
    private(set) var recentMaps: [MindMap] = []
    var destination = Destination.newMap
    var newMapTitle = ""

    var canSave: Bool {
        phase == .ready && (!topics.isEmpty || fileCount > 0)
    }

    private var contents: [SharedContent] = []
    private var files: [(url: URL, kind: ShareInbox.Kind)] = []
    private let capture: QuickCapture?
    private let inbox: ShareInbox?
    private static let log = Logger(subsystem: "asia.xdev.mindmapai.share", category: "Share")

    init(capture: QuickCapture?, inbox: ShareInbox?) {
        self.capture = capture
        self.inbox = inbox
    }

    /// The store the app made in the App Group. The extension never creates it:
    /// see `AppGroup.hasStore`.
    static func live() -> ShareModel {
        guard let container = AppGroup.containerURL(), AppGroup.hasStore(in: container) else {
            return ShareModel(capture: nil, inbox: nil)
        }
        do {
            let repository = try PersistenceController.makeRepository(at: .file(AppGroup.storeURL(in: container)))
            return ShareModel(capture: QuickCapture(repository: repository), inbox: ShareInbox(containerURL: container))
        } catch {
            log.error("The shared store did not open: \(error.localizedDescription, privacy: .public)")
            return ShareModel(capture: nil, inbox: nil)
        }
    }

    func load(from items: [NSExtensionItem]) async {
        guard let capture else {
            phase = .needsApp
            return
        }
        for item in items {
            // Safari puts the page title here, next to the URL attachment.
            let title = item.attributedContentText?.string ?? item.attributedTitle?.string
            for provider in item.attachments ?? [] {
                await read(provider, linkTitle: title)
            }
        }
        topics = SharedContent.outline(of: contents).items.filter { $0.depth == 0 }.map(\.title)
        fileCount = files.count
        do {
            recentMaps = try await capture.recentMaps()
            phase = .ready
        } catch {
            Self.log.error("Loading maps failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed
        }
    }

    /// True when the share is done and the sheet can close.
    func save() async -> Bool {
        guard let capture, let inbox, canSave else { return false }
        phase = .saving
        do {
            let draft = SharedContent.outline(of: contents)
            let mapID: MapID
            switch destination {
            case .existing(let id):
                if !draft.isEmpty { try await capture.add(draft, to: id) }
                mapID = id
            case .newMap:
                mapID = try await createMap(from: draft, with: capture)
            }
            for file in files {
                try inbox.add(fileAt: file.url, kind: file.kind, targetMapID: mapID)
            }
            return true
        } catch {
            Self.log.error("Saving the share failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed
            return false
        }
    }

    /// A typed title names the central topic and everything shared goes under
    /// it; without one, the import rules name the map (one top-level topic
    /// becomes the central topic).
    private func createMap(from draft: OutlineDraft, with capture: QuickCapture) async throws -> MapID {
        let title = newMapTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let untitled = String(localized: "Untitled Map")
        if title.isEmpty, !draft.isEmpty {
            return try await capture.createMap(from: draft, title: untitled).id
        }
        let map = try await capture.createMap(from: OutlineDraft(), title: title.isEmpty ? untitled : title)
        if !draft.isEmpty { try await capture.add(draft, to: map.id) }
        return map.id
    }

    // MARK: Reading attachments

    private func read(_ provider: NSItemProvider, linkTitle: String?) async {
        do {
            if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                files.append((try await copy(provider, type: .pdf), .pdf))
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                files.append((try await copy(provider, type: .image), .image))
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                      let url = try await loadURL(provider), !url.isFileURL {
                contents.append(.link(url, title: linkTitle))
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                      let text = try await loadText(provider) {
                contents.append(.text(text))
            }
        } catch {
            // One unreadable attachment should not lose the others.
            Self.log.error("Reading a shared item failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadURL(_ provider: NSItemProvider) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: item as? URL) }
            }
        }
    }

    private func loadText(_ provider: NSItemProvider) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let text = item as? String {
                    continuation.resume(returning: text)
                } else if let data = item as? Data {
                    continuation.resume(returning: try? InterchangeText.decode(data))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// The provider's file is deleted when the handler returns, so it is copied
    /// to a temporary folder first; the inbox copies it again on Save.
    private func copy(_ provider: NSItemProvider, type: UTType) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                guard let url else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                    return
                }
                do {
                    let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let copy = folder.appending(path: url.lastPathComponent)
                    try FileManager.default.copyItem(at: url, to: copy)
                    continuation.resume(returning: copy)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

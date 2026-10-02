import Foundation
import MindMapDomain

/// Images and PDFs shared to the app wait here, in the App Group container,
/// until the app turns them into topics (OCR or AI, FR-SYS-02). The Share
/// Extension only copies files: it never loads a model, so it stays light.
///
/// One folder per item holds the file and an `item.json` describing it, so an
/// item is complete or absent, never half written.
public struct ShareInbox: Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case image
        case pdf
    }

    public struct Item: Codable, Hashable, Sendable, Identifiable {
        public let id: UUID
        public let kind: Kind
        /// The file name inside the item's folder, as the sender named it.
        public let fileName: String
        /// The map the user chose; nil means "a new map".
        public let targetMapID: MapID?
        public let createdAt: Date
    }

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The inbox in the App Group container.
    public init(containerURL: URL) {
        self.init(directory: containerURL.appending(path: "Inbox", directoryHint: .isDirectory))
    }

    /// Copies the file: the sender's copy may be gone once the share sheet closes.
    @discardableResult
    public func add(fileAt source: URL, kind: Kind, targetMapID: MapID?, now: Date = .now) throws -> Item {
        let fileManager = FileManager.default
        let item = Item(id: UUID(), kind: kind, fileName: source.lastPathComponent, targetMapID: targetMapID, createdAt: now)
        let staging = directory.appending(path: ".\(item.id.uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            try fileManager.copyItem(at: source, to: staging.appending(path: item.fileName))
            try JSONEncoder().encode(item).write(to: staging.appending(path: "item.json"))
            // Renaming the finished folder into place is what makes the item visible.
            try fileManager.moveItem(at: staging, to: folder(of: item))
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
        return item
    }

    /// Oldest first. Folders without a readable description are skipped.
    public func items() throws -> [Item] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path(percentEncoded: false)) else { return [] }
        let folders = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        return folders
            .compactMap { try? JSONDecoder().decode(Item.self, from: Data(contentsOf: $0.appending(path: "item.json"))) }
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
    }

    public func fileURL(of item: Item) -> URL {
        folder(of: item).appending(path: item.fileName)
    }

    public func remove(_ item: Item) throws {
        try FileManager.default.removeItem(at: folder(of: item))
    }

    private func folder(of item: Item) -> URL {
        directory.appending(path: item.id.uuidString, directoryHint: .isDirectory)
    }
}

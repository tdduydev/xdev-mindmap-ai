import Foundation
import MindMapInterchange
import UniformTypeIdentifiers

/// A text file read and parsed, ready to become a map or join one.
nonisolated struct ImportedFile: Sendable {
    /// The file name without its extension: the new map's name when the file has several top-level topics.
    let name: String
    let format: InterchangeFormat
    let draft: OutlineDraft
}

/// Why an import stopped, worded for the alert (FR-IO-09). Each case names the
/// file and says what the app does read.
nonisolated enum ImportFailure: Error, Equatable, Sendable {
    case unsupportedType(fileName: String)
    case unreadableText(fileName: String)
    case emptyDocument(fileName: String)
    case couldNotRead(fileName: String)
    /// A `.json` file that is not a MindMap AI backup.
    case notABackup(fileName: String)
    /// A backup written by a newer version of the app.
    case newerBackup(fileName: String)
    /// A backup with a record that is missing or wrong.
    case damagedBackup(fileName: String)
    /// Import into Map… was given a backup, which is a whole map.
    case backupIntoMap(fileName: String)
    /// The open panel reported an error instead of a file.
    case couldNotOpenPanel
    /// The map or the new topics could not be saved.
    case couldNotSave

    var title: String {
        switch self {
        case .unsupportedType(let name), .unreadableText(let name), .emptyDocument(let name), .couldNotRead(let name),
             .notABackup(let name), .newerBackup(let name), .damagedBackup(let name), .backupIntoMap(let name):
            String(localized: "Can’t Import “\(name)”")
        case .couldNotOpenPanel, .couldNotSave:
            String(localized: "Couldn’t Import File")
        }
    }

    var message: String {
        switch self {
        case .unsupportedType:
            String(localized: "MindMap AI imports Markdown (.md) and plain text (.txt) files, and its own backups (.json).")
        case .unreadableText:
            String(localized: "The file isn’t UTF-8 or UTF-16 text. Save it as UTF-8 Markdown or plain text, then try again.")
        case .emptyDocument:
            String(localized: "The file has no topics in it. MindMap AI reads headings and list items in Markdown, and one topic per line in plain text.")
        case .couldNotRead:
            String(localized: "MindMap AI couldn’t read the file. Check that it opens in another app, then try again.")
        case .notABackup:
            String(localized: "The file is JSON but not a MindMap AI backup. MindMap AI imports backups made with File ▸ Export… ▸ MindMap AI Backup.")
        case .newerBackup:
            String(localized: "The backup was made by a newer version of MindMap AI. Update the app, then try again.")
        case .damagedBackup:
            String(localized: "The backup is damaged and can’t be read. Try another copy of it.")
        case .backupIntoMap:
            String(localized: "A backup is a whole map. Choose File ▸ Import… to open it as a new map.")
        case .couldNotOpenPanel:
            String(localized: "The file couldn’t be opened. Try again.")
        case .couldNotSave:
            String(localized: "The imported topics couldn’t be saved. Try again.")
        }
    }
}

/// Reads a file the user picked in File ▸ Import… (FR-IO-08). Parsing is in
/// `MindMapInterchange`; this only opens the file and picks the format.
nonisolated enum MapImporter {
    /// What the open panel offers. Rich text and other text files stay
    /// pickable so the user gets the message of FR-IO-09 rather than a greyed-out file.
    static let contentTypes: [UTType] = [.markdownText, .plainText, .text, .json]

    /// Decoding and parsing run off the main actor, so a large file does not stall the window.
    @concurrent
    static func read(_ url: URL) async throws(ImportFailure) -> ImportedFile {
        let fileName = url.lastPathComponent
        guard let format = format(of: url) else { throw .unsupportedType(fileName: fileName) }

        // Files from the open panel are outside the sandbox until accessed this way.
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .couldNotRead(fileName: fileName)
        }

        let draft: OutlineDraft
        do {
            draft = try await format.parse(data)
        } catch {
            throw .unreadableText(fileName: fileName)
        }
        guard !draft.isEmpty else { throw .emptyDocument(fileName: fileName) }
        return ImportedFile(name: url.deletingPathExtension().lastPathComponent, format: format, draft: draft)
    }

    /// Whether the file is read as a backup (`MapArchive`) instead of as text.
    static func isBackup(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == MapArchive.fileExtension
    }

    /// A backup becomes a new map with new IDs, so it never replaces a map in
    /// the library (docs/interchange.md, Map archive).
    @concurrent
    static func readBackup(_ url: URL) async throws(ImportFailure) -> MapArchive {
        let fileName = url.lastPathComponent
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .couldNotRead(fileName: fileName)
        }
        do {
            return try await MapArchive.decode(data)
        } catch {
            switch error {
            case .notAnArchive: throw .notABackup(fileName: fileName)
            case .newerVersion: throw .newerBackup(fileName: fileName)
            case .damaged: throw .damagedBackup(fileName: fileName)
            }
        }
    }

    /// By extension first; then any other plain text (a `.text` or `.log`
    /// file) reads as indented text. Rich text, HTML and binary files are refused.
    static func format(of url: URL) -> InterchangeFormat? {
        let fileExtension = url.pathExtension
        if let format = InterchangeFormat(fileExtension: fileExtension) { return format }
        guard let type = UTType(filenameExtension: fileExtension) else { return nil }
        if type.conforms(to: .markdownText) { return .markdown }
        if type.conforms(to: .plainText) { return .plainText }
        return nil
    }
}

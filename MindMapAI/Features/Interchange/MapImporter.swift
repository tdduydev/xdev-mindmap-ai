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
    /// The open panel reported an error instead of a file.
    case couldNotOpenPanel
    /// The map or the new topics could not be saved.
    case couldNotSave

    var title: String {
        switch self {
        case .unsupportedType(let name), .unreadableText(let name), .emptyDocument(let name), .couldNotRead(let name):
            String(localized: "Can’t Import “\(name)”")
        case .couldNotOpenPanel, .couldNotSave:
            String(localized: "Couldn’t Import File")
        }
    }

    var message: String {
        switch self {
        case .unsupportedType:
            String(localized: "MindMap AI imports Markdown (.md) and plain text (.txt) files.")
        case .unreadableText:
            String(localized: "The file isn’t UTF-8 or UTF-16 text. Save it as UTF-8 Markdown or plain text, then try again.")
        case .emptyDocument:
            String(localized: "The file has no topics in it. MindMap AI reads headings and list items in Markdown, and one topic per line in plain text.")
        case .couldNotRead:
            String(localized: "MindMap AI couldn’t read the file. Check that it opens in another app, then try again.")
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
    static let contentTypes: [UTType] = [.markdownText, .plainText, .text]

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

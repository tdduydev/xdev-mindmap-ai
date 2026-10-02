import Foundation
import MindMapDomain
import MindMapGraph

/// A text format a map can be read from and written to.
public enum InterchangeFormat: String, Hashable, Sendable, CaseIterable {
    case markdown
    case plainText

    /// Nil for an extension no format reads, so the caller can say which ones do.
    public init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "md", "markdown", "mdown", "mkd": self = .markdown
        case "txt", "text": self = .plainText
        default: return nil
        }
    }

    public var fileExtension: String {
        switch self {
        case .markdown: "md"
        case .plainText: "txt"
        }
    }

    public func parse(_ text: String) -> OutlineDraft {
        switch self {
        case .markdown: MarkdownOutline.parse(text)
        case .plainText: PlainTextOutline.parse(text)
        }
    }

    /// Decodes and parses file contents. Runs off the caller's actor, since a
    /// large file takes a while and the editor must stay responsive.
    @concurrent
    public func parse(_ data: Data) async throws -> OutlineDraft {
        parse(try InterchangeText.decode(data))
    }

    /// The map, or one branch, in this format. Notes are left out when
    /// `includeNotes` is false.
    public func export(_ state: GraphState, branch branchID: NodeID? = nil, includeNotes: Bool = true) throws -> String {
        switch self {
        case .markdown:
            try MarkdownOutline.export(state, branch: branchID, options: .init(includeNotes: includeNotes))
        case .plainText:
            try PlainTextOutline.export(state, branch: branchID, includeNotes: includeNotes)
        }
    }

    @concurrent
    public func exportData(_ state: GraphState, branch branchID: NodeID? = nil, includeNotes: Bool = true) async throws -> Data {
        Data(try export(state, branch: branchID, includeNotes: includeNotes).utf8)
    }
}

public enum InterchangeError: Error, Hashable, Sendable {
    /// Not text in an encoding the app reads: binary data, or a legacy encoding.
    case unreadableText
    /// The file has no topics in it.
    case emptyDocument
    /// The branch to export is not in the map.
    case topicNotFound
}

/// Turns file bytes into text.
public enum InterchangeText {
    /// UTF-8, with or without a byte order mark, or UTF-16 with one. Anything
    /// else is refused rather than guessed: a wrong guess (say, a Vietnamese
    /// legacy encoding read as Latin-1) would import garbage without warning.
    public static func decode(_ data: Data) throws -> String {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            guard let text = String(data: data, encoding: .utf16) else { throw InterchangeError.unreadableText }
            return text
        }
        let bytes = data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data[...]
        // A NUL byte never appears in text; it marks a binary file.
        guard !bytes.contains(0), let text = String(validating: bytes, as: UTF8.self) else {
            throw InterchangeError.unreadableText
        }
        return text
    }
}

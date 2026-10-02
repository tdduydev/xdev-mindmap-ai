import Foundation
import MindMapGraph
import SwiftUI
import UniformTypeIdentifiers

/// Turns a map into the bytes of an exported file. Text comes from
/// `MindMapInterchange` off the main actor; pictures are laid out off it and
/// drawn on it, since `ImageRenderer` is main-actor only.
enum MapExporter {
    /// - Parameter colorScheme: The appearance a picture takes when its
    ///   background matches the appearance.
    static func data(for graph: GraphState, options: ExportOptions, colorScheme: ColorScheme) async throws -> Data {
        if let format = options.format.interchange {
            return try await format.exportData(graph, branch: options.branch, includeNotes: options.includeNotes)
        }
        let picture = await MapPicture.make(graph)
        switch options.format {
        case .png:
            return try MapRenderer.png(
                picture,
                scale: CGFloat(options.imageScale.rawValue),
                background: options.background,
                colorScheme: colorScheme
            )
        case .pdf:
            let layout = PDFPageLayout(
                content: picture.size,
                paper: options.paper.size,
                mode: options.pageMode,
                margin: CanvasMetrics.exportPageMargin
            )
            return try MapRenderer.pdf(
                picture,
                layout: layout,
                background: options.background,
                colorScheme: colorScheme,
                title: graph.map.title
            )
        case .markdown, .plainText:
            preconditionFailure("Text formats return above")
        }
    }

    /// The map's title, made safe as a file name; the save panel adds the extension.
    static func fileName(for title: String) -> String {
        let cleaned = title
            .components(separatedBy: CharacterSet(charactersIn: "/:\\").union(.newlines).union(.controlCharacters))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? String(localized: "Untitled Map") : cleaned
    }
}

/// The bytes handed to `fileExporter`.
nonisolated struct ExportedFile: FileDocument {
    static let readableContentTypes: [UTType] = []

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        // Export only writes.
        throw CocoaError(.featureUnsupported)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

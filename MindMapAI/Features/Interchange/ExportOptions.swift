import Foundation
import MindMapDomain
import MindMapInterchange
import UniformTypeIdentifiers

/// A file type File ▸ Export… writes.
enum ExportFormat: String, CaseIterable, Identifiable {
    case markdown
    case plainText
    case png
    case pdf

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .markdown: "Markdown"
        case .plainText: "Plain Text"
        case .png: "PNG Image"
        case .pdf: "PDF"
        }
    }

    /// The text format behind Markdown and plain text; nil for pictures.
    var interchange: InterchangeFormat? {
        switch self {
        case .markdown: .markdown
        case .plainText: .plainText
        case .png, .pdf: nil
        }
    }

    var contentType: UTType {
        switch self {
        case .markdown: .markdownText
        case .plainText: .plainText
        case .png: .png
        case .pdf: .pdf
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown: "md"
        case .plainText: "txt"
        case .png: "png"
        case .pdf: "pdf"
        }
    }
}

extension UTType {
    /// Markdown as the system declares it; plain text where it does not, which
    /// still lets the open panel show and pick `.md` files.
    nonisolated static let markdownText = UTType("net.daringfireball.markdown")
        ?? UTType(filenameExtension: "md", conformingTo: .plainText)
        ?? .plainText
}

/// Behind an exported picture: the canvas colour of the current appearance,
/// or white paper (FR-IO-04).
enum ExportBackground: String, CaseIterable, Identifiable {
    case appearance
    case white

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .appearance: "Match Appearance"
        case .white: "White"
        }
    }
}

/// Pixels per canvas point in an exported PNG.
enum ImageScale: Int, CaseIterable, Identifiable {
    case standard = 1
    case double = 2
    case triple = 3

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .standard: "Standard (1×)"
        case .double: "High (2×)"
        case .triple: "Very High (3×)"
        }
    }

    /// High resolution is part of MindMap AI Pro (docs/pricing.md).
    var requiredFeature: ProFeature? {
        self == .standard ? nil : .highResolutionImage
    }
}

/// How a PDF lays the map out (FR-IO-05).
nonisolated enum PDFPageMode: String, CaseIterable, Identifiable {
    /// The whole map scaled down to one page.
    case singlePage
    /// The map at actual size, split over as many pages as it needs.
    case multiplePages

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .singlePage: "Fit to One Page"
        case .multiplePages: "Actual Size on Several Pages"
        }
    }

    var requiredFeature: ProFeature? {
        self == .multiplePages ? .multiPagePDF : nil
    }
}

/// Paper sizes in PDF points (1/72 inch), portrait.
enum PaperSize: String, CaseIterable, Identifiable {
    case a4
    case letter

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .a4: "A4"
        case .letter: "US Letter"
        }
    }

    var size: CGSize {
        switch self {
        case .a4: CGSize(width: 595.28, height: 841.89)
        case .letter: CGSize(width: 612, height: 792)
        }
    }

    /// US Letter where it is the common paper, A4 everywhere else.
    static func preferred(for locale: Locale = .current) -> PaperSize {
        let letterRegions: Set<String> = ["US", "CA", "MX", "PH", "CL", "CO", "VE", "PR", "GT", "CR", "DO", "SV", "PA"]
        guard let region = locale.region?.identifier else { return .a4 }
        return letterRegions.contains(region) ? .letter : .a4
    }
}

/// Everything the export sheet asks for.
struct ExportOptions: Equatable {
    var format: ExportFormat = .markdown
    /// Text formats only: nil exports the whole map.
    var branch: NodeID?
    var includeNotes = true
    var background: ExportBackground = .appearance
    var imageScale: ImageScale = .double
    var pageMode: PDFPageMode = .singlePage
    var paper: PaperSize = .preferred()

    /// The Pro feature the chosen options need, if any.
    var requiredFeature: ProFeature? {
        switch format {
        case .markdown, .plainText: nil
        case .png: imageScale.requiredFeature
        case .pdf: pageMode.requiredFeature
        }
    }
}

/// The export defaults kept in Settings (FR-SET-07).
enum ExportPreferences {
    static let includeNotesKey = "export.includeNotes"
}

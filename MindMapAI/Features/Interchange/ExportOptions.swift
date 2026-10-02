import Foundation
import MindMapDomain
import MindMapInterchange
import SwiftUI
import UniformTypeIdentifiers

/// A file type File ▸ Export… writes.
enum ExportFormat: String, CaseIterable, Identifiable {
    case markdown
    case plainText
    case png
    case pdf
    /// Everything in the map, to import again without loss (`MapArchive`).
    case backup

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .markdown: "Markdown"
        case .plainText: "Plain Text"
        case .png: "PNG Image"
        case .pdf: "PDF"
        case .backup: "MindMap AI Backup"
        }
    }

    /// The text format behind Markdown and plain text; nil for pictures.
    var interchange: InterchangeFormat? {
        switch self {
        case .markdown: .markdown
        case .plainText: .plainText
        case .png, .pdf, .backup: nil
        }
    }

    var contentType: UTType {
        switch self {
        case .markdown: .markdownText
        case .plainText: .plainText
        case .png: .png
        case .pdf: .pdf
        case .backup: .json
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown: "md"
        case .plainText: "txt"
        case .png: "png"
        case .pdf: "pdf"
        case .backup: MapArchive.fileExtension
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
        self == .standard ? nil : .highResolutionPNGExport
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
        self == .multiplePages ? .vectorPDFExport : nil
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
        case .markdown, .plainText, .backup: nil
        case .png: imageScale.requiredFeature
        case .pdf: pageMode.requiredFeature
        }
    }
}

/// The export defaults in Settings ▸ Export (FR-SET-07). The export sheet
/// starts from them and writes back what is changed in it, through the same
/// keys, so Settings and the sheet never disagree.
struct ExportPreferences {
    static let formatKey = "export.format"
    static let includeNotesKey = "export.includeNotes"
    static let imageScaleKey = "export.png.scale"
    static let pageModeKey = "export.pdf.pages"
    /// Absent means Automatic: the paper of the region (`PaperSize.preferred()`).
    static let paperKey = "export.pdf.paper"
    static let backgroundKey = "export.background"

    var defaults: UserDefaults = AppDefaults.store

    /// The stored PNG resolution, or the default when none is stored: High
    /// with Pro, Standard without (docs/settings.md).
    static func imageScale(stored: ImageScale?, entitlements: any ProEntitlements) -> ImageScale {
        let allowsHigh = entitlements.allows(.highResolutionPNGExport)
        guard let stored else { return allowsHigh ? .double : .standard }
        // A stored Pro choice stays stored without Pro; the export uses the best it may.
        return stored.requiredFeature.map { entitlements.allows($0) } == false ? .standard : stored
    }

    /// What the export sheet opens with. Pro choices without Pro become their
    /// free counterparts, so the sheet never opens on a locked option.
    func options(entitlements: any ProEntitlements, locale: Locale = .current) -> ExportOptions {
        var options = ExportOptions()
        if let format = defaults.string(forKey: Self.formatKey).flatMap(ExportFormat.init(rawValue:)) {
            options.format = format
        }
        if defaults.object(forKey: Self.includeNotesKey) != nil {
            options.includeNotes = defaults.bool(forKey: Self.includeNotesKey)
        }
        let storedScale = defaults.object(forKey: Self.imageScaleKey) == nil
            ? nil : ImageScale(rawValue: defaults.integer(forKey: Self.imageScaleKey))
        options.imageScale = Self.imageScale(stored: storedScale, entitlements: entitlements)
        let pageMode = defaults.string(forKey: Self.pageModeKey).flatMap(PDFPageMode.init(rawValue:)) ?? .singlePage
        options.pageMode = pageMode.requiredFeature.map { entitlements.allows($0) } == false ? .singlePage : pageMode
        options.paper = defaults.string(forKey: Self.paperKey).flatMap(PaperSize.init(rawValue:)) ?? .preferred(for: locale)
        if let background = defaults.string(forKey: Self.backgroundKey).flatMap(ExportBackground.init(rawValue:)) {
            options.background = background
        }
        return options
    }

    /// Stores what changed between two sheet states, and only that: a paper
    /// size or resolution nobody touched stays Automatic or default.
    func save(_ options: ExportOptions, changedFrom old: ExportOptions) {
        if options.format != old.format { defaults.set(options.format.rawValue, forKey: Self.formatKey) }
        if options.includeNotes != old.includeNotes { defaults.set(options.includeNotes, forKey: Self.includeNotesKey) }
        if options.imageScale != old.imageScale { defaults.set(options.imageScale.rawValue, forKey: Self.imageScaleKey) }
        if options.pageMode != old.pageMode { defaults.set(options.pageMode.rawValue, forKey: Self.pageModeKey) }
        if options.paper != old.paper { defaults.set(options.paper.rawValue, forKey: Self.paperKey) }
        if options.background != old.background { defaults.set(options.background.rawValue, forKey: Self.backgroundKey) }
    }
}

import Foundation

/// Everything MindMap AI Pro unlocks, in one place (docs/pricing.md). A feature
/// asks `ProEntitlement.allows(_:)` before running; anything not listed here is
/// free and must never ask. Only features the app has belong here: the paywall
/// lists every case, and promising one that is not built breaks App Review
/// 2.3.1 (OPML waits until FR-IO-06 is built).
enum ProFeature: CaseIterable, Identifiable {
    case vectorPDFExport
    case highResolutionPNGExport
    case extraThemes
    case generateMapFromDescription
    case summarizeWholeMap
    case findMissingIdeas
    case voiceInput

    var id: Self { self }

    /// Runs on the on-device model, so it does not exist on a Mac that can
    /// never run Apple Intelligence (an Intel Mac, MM-21).
    var needsOnDeviceModel: Bool {
        switch self {
        case .generateMapFromDescription, .summarizeWholeMap, .findMissingIdeas: true
        case .vectorPDFExport, .highResolutionPNGExport, .extraThemes, .voiceInput: false
        }
    }

    /// What the paywall may promise: without AI, Pro must not list AI tools
    /// the buyer can never use (App Review 2.3.1).
    static func offered(includingAI: Bool) -> [ProFeature] {
        allCases.filter { includingAI || !$0.needsOnDeviceModel }
    }

    var title: LocalizedStringResource {
        switch self {
        case .vectorPDFExport: "Multi-Page Vector PDF Export"
        case .highResolutionPNGExport: "High-Resolution PNG Export"
        case .extraThemes: "More Themes"
        case .generateMapFromDescription: "Generate a Map from a Long Description"
        case .summarizeWholeMap: "Summarize a Whole Map"
        case .findMissingIdeas: "Find Missing Topics"
        case .voiceInput: "Voice Input"
        }
    }

    var systemImage: String {
        switch self {
        case .vectorPDFExport: "doc.richtext"
        case .highResolutionPNGExport: "photo"
        case .extraThemes: "paintpalette"
        case .generateMapFromDescription: "text.badge.plus"
        case .summarizeWholeMap: "text.append"
        case .findMissingIdeas: "lightbulb"
        case .voiceInput: "mic"
        }
    }
}

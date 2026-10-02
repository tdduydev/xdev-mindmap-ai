import SwiftUI

/// Settings ▸ Export (FR-SET-07): what the export sheet starts with. The sheet
/// writes the same keys (`ExportPreferences`), so a change in either shows in both.
struct ExportSettingsSection: View {
    @AppStorage(ExportPreferences.includeNotesKey, store: AppDefaults.store) private var includeNotes = true
    /// Nil until chosen: the default depends on Pro (`ExportPreferences.imageScale`).
    @AppStorage(ExportPreferences.imageScaleKey, store: AppDefaults.store) private var imageScale: ImageScale?
    @AppStorage(ExportPreferences.pageModeKey, store: AppDefaults.store) private var pageMode = PDFPageMode.singlePage
    /// Nil is Automatic: the paper of the region.
    @AppStorage(ExportPreferences.paperKey, store: AppDefaults.store) private var paper: PaperSize?
    @AppStorage(ExportPreferences.backgroundKey, store: AppDefaults.store) private var background = ExportBackground.appearance
    @Environment(ProEntitlement.self) private var pro
    @State private var paywall: PendingProChoice?

    /// The stored choice even when Pro is missing; the export itself uses the best allowed.
    private var shownScale: ImageScale {
        imageScale ?? ExportPreferences.imageScale(stored: nil, entitlements: pro)
    }

    private func isLocked(_ feature: ProFeature?) -> Bool {
        feature.map { !pro.allows($0) } ?? false
    }

    private var hasLockedChoice: Bool {
        isLocked(shownScale.requiredFeature) || isLocked(pageMode.requiredFeature)
    }

    var body: some View {
        Section {
            Toggle("Include Notes", isOn: $includeNotes)
                .accessibilityIdentifier(AccessibilityID.Settings.includeNotes)
        } footer: {
            Text("Applies to Markdown and plain text exports.")
        }

        Section {
            Picker("PNG Resolution", selection: Binding(get: { shownScale }, set: choose)) {
                ForEach(ImageScale.allCases) { scale in
                    ProChoiceLabel(title: scale.title, isLocked: isLocked(scale.requiredFeature))
                        .tag(scale)
                }
            }
            .accessibilityIdentifier(AccessibilityID.Settings.pngResolution)
            Picker("PDF Pages", selection: Binding(get: { pageMode }, set: choose)) {
                ForEach(PDFPageMode.allCases) { mode in
                    ProChoiceLabel(title: mode.title, isLocked: isLocked(mode.requiredFeature))
                        .tag(mode)
                }
            }
            .accessibilityIdentifier(AccessibilityID.Settings.pdfPages)
            Picker("Paper Size", selection: $paper) {
                Text("Automatic").tag(PaperSize?.none)
                ForEach(PaperSize.allCases) { size in
                    Text(size.title).tag(PaperSize?.some(size))
                }
            }
            .accessibilityIdentifier(AccessibilityID.Settings.paperSize)
            Picker("Background", selection: $background) {
                ForEach(ExportBackground.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .accessibilityIdentifier(AccessibilityID.Settings.background)
        } footer: {
            if hasLockedChoice {
                Text("Choices with a star come with MindMap AI Pro. Until it’s unlocked, exports use Standard (1×) and one page.")
            } else {
                Text("Background applies to PNG and PDF. Automatic uses the usual paper of your region.")
            }
        }
        .proChoicePaywall($paywall)
    }

    private func choose(_ scale: ImageScale) {
        if let feature = scale.requiredFeature, isLocked(feature) {
            paywall = PendingProChoice(feature: feature) { imageScale = scale }
        } else {
            imageScale = scale
        }
    }

    private func choose(_ mode: PDFPageMode) {
        if let feature = mode.requiredFeature, isLocked(feature) {
            paywall = PendingProChoice(feature: feature) { pageMode = mode }
        } else {
            pageMode = mode
        }
    }
}

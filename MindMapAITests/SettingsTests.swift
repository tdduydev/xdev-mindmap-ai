import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import SwiftUI
import Testing

/// Settings ▸ General and Export (MM-43): the defaults of docs/settings.md, Pro
/// fallback, and that Settings and the places that use a value read one key.
@Suite("Settings")
struct SettingsTests {
    let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: "SettingsTests.\(UUID().uuidString)"))
    }

    private let us = Locale(identifier: "en_US")
    private let vietnam = Locale(identifier: "vi_VN")

    // MARK: Panes

    @Test func panesAreInTheDocumentedOrder() {
        #expect(SettingsPane.available(showsAI: true) == [.general, .export, .ai, .data, .pro, .privacy, .about])
        #expect(SettingsPane.available(showsAI: false) == [.general, .export, .data, .pro, .privacy, .about])
    }

    @Test func lastPaneReopensAndAMissingOneOpensGeneral() {
        let stored = AppStorage(wrappedValue: SettingsPane.general, SettingsPane.storageKey, store: defaults)
        #expect(stored.wrappedValue == .general)
        stored.wrappedValue = .export
        #expect(AppStorage(wrappedValue: SettingsPane.general, SettingsPane.storageKey, store: defaults).wrappedValue == .export)

        // AI was last, then the Mac turned out to have no Apple Intelligence (an Intel Mac).
        #expect(SettingsPane.ai.resolved(in: SettingsPane.available(showsAI: false)) == .general)
        defaults.set("aiApps", forKey: SettingsPane.storageKey)
        #expect(AppStorage(wrappedValue: SettingsPane.general, SettingsPane.storageKey, store: defaults).wrappedValue == .general)
    }

    // MARK: Theme for New Maps

    @Test func newMapsAreStandardByDefault() {
        #expect(NewMapPreferences.theme(in: defaults, entitlements: Unlocked()) == .standard)
        #expect(NewMapPreferences.theme(in: defaults, entitlements: Locked()) == .standard)
    }

    @Test func settingsPickerAndNewMapReadTheSameKey() {
        AppStorage(wrappedValue: MindMapTheme.standard, NewMapPreferences.themeKey, store: defaults).wrappedValue = .graphite
        #expect(NewMapPreferences.theme(in: defaults, entitlements: Unlocked()) == .graphite)
    }

    @Test func proThemeWithoutProFallsBackAndIsKept() {
        defaults.set(MindMapTheme.xdevBlue.rawValue, forKey: NewMapPreferences.themeKey)

        // Refunded: new maps are Standard, the choice stays for when Pro comes back.
        #expect(NewMapPreferences.theme(in: defaults, entitlements: Locked()) == .standard)
        #expect(defaults.string(forKey: NewMapPreferences.themeKey) == MindMapTheme.xdevBlue.rawValue)
        #expect(NewMapPreferences.theme(in: defaults, entitlements: Unlocked()) == .xdevBlue)
    }

    @Test func unknownStoredThemeGivesStandard() {
        defaults.set("aurora", forKey: NewMapPreferences.themeKey)
        #expect(NewMapPreferences.theme(in: defaults, entitlements: Unlocked()) == .standard)
    }

    @Test func newMindMapGetsTheTheme() async throws {
        let repository = try PersistenceController.makeRepository(at: .inMemory)
        let library = LibraryModel(repository: repository)

        let id = try #require(await library.createMap(theme: .graphite))

        let graph = try #require(try await repository.loadGraph(for: id))
        #expect(graph.map.theme == .graphite)
        #expect(library.maps.first?.theme == .graphite)
    }

    // MARK: Export

    @Test func exportDefaults() {
        let free = ExportPreferences(defaults: defaults).options(entitlements: Locked(), locale: us)
        #expect(free.format == .markdown)
        #expect(free.includeNotes)
        #expect(free.imageScale == .standard)
        #expect(free.pageMode == .singlePage)
        #expect(free.paper == .letter)
        #expect(free.background == .appearance)

        let pro = ExportPreferences(defaults: defaults).options(entitlements: Unlocked(), locale: vietnam)
        #expect(pro.imageScale == .double)
        #expect(pro.paper == .a4)
    }

    /// Settings writes through `@AppStorage`; the sheet reads through `ExportPreferences`.
    @Test func settingsAndSheetShareKeys() {
        AppStorage(wrappedValue: true, ExportPreferences.includeNotesKey, store: defaults).wrappedValue = false
        AppStorage<ImageScale?>(ExportPreferences.imageScaleKey, store: defaults).wrappedValue = .triple
        AppStorage(wrappedValue: PDFPageMode.singlePage, ExportPreferences.pageModeKey, store: defaults).wrappedValue = .multiplePages
        AppStorage<PaperSize?>(ExportPreferences.paperKey, store: defaults).wrappedValue = .a4
        AppStorage(wrappedValue: ExportBackground.appearance, ExportPreferences.backgroundKey, store: defaults).wrappedValue = .white

        let options = ExportPreferences(defaults: defaults).options(entitlements: Unlocked(), locale: us)
        #expect(!options.includeNotes)
        #expect(options.imageScale == .triple)
        #expect(options.pageMode == .multiplePages)
        #expect(options.paper == .a4)
        #expect(options.background == .white)
    }

    @Test func sheetChangesShowInSettings() {
        let preferences = ExportPreferences(defaults: defaults)
        let opened = preferences.options(entitlements: Unlocked(), locale: us)
        var changed = opened
        changed.format = .pdf
        changed.background = .white
        changed.imageScale = .triple

        preferences.save(changed, changedFrom: opened)

        #expect(AppStorage(wrappedValue: ExportBackground.appearance, ExportPreferences.backgroundKey, store: defaults).wrappedValue == .white)
        #expect(AppStorage<ImageScale?>(ExportPreferences.imageScaleKey, store: defaults).wrappedValue == .triple)
        #expect(preferences.options(entitlements: Unlocked(), locale: us).format == .pdf)
        // Untouched values stay unset, so Paper Size is still Automatic.
        #expect(AppStorage<PaperSize?>(ExportPreferences.paperKey, store: defaults).wrappedValue == nil)
        #expect(defaults.object(forKey: ExportPreferences.pageModeKey) == nil)
    }

    @Test func automaticPaperFollowsTheRegion() {
        let preferences = ExportPreferences(defaults: defaults)
        #expect(preferences.options(entitlements: Locked(), locale: us).paper == .letter)
        #expect(preferences.options(entitlements: Locked(), locale: vietnam).paper == .a4)
    }

    @Test func proExportChoicesWithoutProFallBackAndAreKept() {
        defaults.set(ImageScale.triple.rawValue, forKey: ExportPreferences.imageScaleKey)
        defaults.set(PDFPageMode.multiplePages.rawValue, forKey: ExportPreferences.pageModeKey)
        let preferences = ExportPreferences(defaults: defaults)

        let locked = preferences.options(entitlements: Locked(), locale: us)
        #expect(locked.imageScale == .standard)
        #expect(locked.pageMode == .singlePage)
        #expect(defaults.integer(forKey: ExportPreferences.imageScaleKey) == ImageScale.triple.rawValue)

        let unlocked = preferences.options(entitlements: Unlocked(), locale: us)
        #expect(unlocked.imageScale == .triple)
        #expect(unlocked.pageMode == .multiplePages)
    }
}

private struct Locked: ProEntitlements {
    func allows(_ feature: ProFeature) -> Bool { false }
}

private struct Unlocked: ProEntitlements {
    func allows(_ feature: ProFeature) -> Bool { true }
}

#if os(macOS)
import AppKit
import Foundation
import MindMapCapture
@testable import MindMapAI
import MindMapAICore
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import MindMapTestSupport
import StoreKitTest
import SwiftUI
import Testing

/// The Mac's own interface, drawn off screen from the `sample` fixture of the
/// UI test mode and compared with the references, in light, dark and Increase
/// Contrast; `scripts/snapshot-tests.sh` runs it once in English and once in
/// Vietnamese. It runs while the Mac is locked, which XCUITest cannot
/// (docs/testing.md, Snapshot tests; NFR-TEST-02, NFR-TEST-03).
@MainActor
@Suite("Mac snapshots", .serialized, .enabled(if: Snapshot.mode != nil))
struct MacSnapshotTests {
    static let windowSize = CGSize(width: 1100, height: 700)

    enum Scene: String, CaseIterable {
        case library, canvas, outline
    }

    // MARK: Main window

    @Test(arguments: Scene.allCases)
    func mainWindow(_ scene: Scene) async throws {
        for appearance in SnapshotAppearance.allCases {
            let app = try await SnapshotApp()
            defer { app.tearDown() }
            if scene != .library {
                let plan = try #require(app.mapID(UITestFixture.Title.plan))
                app.environment.openRequests.open(plan)
            }
            let window = SnapshotWindow.open(app.root, size: Self.windowSize, appearance: appearance)
            defer { window.close() }
            if scene == .library {
                try await SnapshotWindow.settle()
            } else {
                let plan = try #require(app.mapID(UITestFixture.Title.plan))
                try await SnapshotWindow.settle { app.environment.openMaps.isOpen(plan) }
                let map = try await app.openMap(plan)
                switch scene {
                case .library, .canvas: break
                case .outline: map.session.presentation = .outline
                }
                try await SnapshotWindow.settle()
            }
            try Snapshot.verify(try await SnapshotWindow.stableCapture(window), named: "\(scene.rawValue).\(appearance.rawValue)")
        }
    }

    // MARK: Panels

    /// The sidebar, the inspector and the AI suggestion bar (FR-AI-15) on
    /// their own: in the window they sit on Liquid Glass, and AppKit draws
    /// nothing of a glass view, or of what it floats over, off screen.
    @Test func panels() async throws {
        for appearance in SnapshotAppearance.allCases {
            let app = try await SnapshotApp()
            defer { app.tearDown() }
            let plan = try #require(app.mapID(UITestFixture.Title.plan))
            let map = try await app.openMap(plan)
            let research = try #require(map.session.engine.state.nodes.values.first { $0.title == UITestFixture.Title.research })
            map.session.selection = research.id
            let marketing = try #require(map.session.engine.state.nodes.values.first { $0.title == UITestFixture.Title.marketing })
            app.provider.enqueue(.proposal(.suggestions(["Launch Event", "Press Kit", "Newsletter"], under: marketing.id)), for: .expandTopic)
            map.assistant.expand(marketing.id)
            await map.assistant.requestSettled()

            let scenes: [(String, AnyView, CGSize)] = [
                ("sidebar", AnyView(SidebarView(selection: .constant(.all))), CGSize(width: 220, height: 400)),
                ("inspector", AnyView(MapInspectorView(session: map.session)), CGSize(width: 320, height: 900)),
            ]
            // ImageRenderer draws SwiftUI itself, glass included, where AppKit
            // draws nothing; it cannot draw Forms or AppKit controls.
            let bar = ImageRenderer(content: app.withEnvironment(AISuggestionBar(assistant: map.assistant)
                .frame(width: 640)
                .background(Palette.canvasBackground)
                .environment(\.colorScheme, appearance == .dark ? .dark : .light)
                .environment(\._colorSchemeContrast, appearance.contrast)))
            bar.scale = 1
            try Snapshot.verify(try #require(bar.cgImage), named: "suggestionBar.\(appearance.rawValue)")
            for (name, view, size) in scenes {
                let window = SnapshotWindow.open(app.withEnvironment(view), size: size, appearance: appearance, styleMask: [.titled])
                defer { window.close() }
                try await SnapshotWindow.settle()
                try Snapshot.verify(try await SnapshotWindow.stableCapture(window), named: "\(name).\(appearance.rawValue)")
            }
        }
    }

    // MARK: Settings

    @Test func settings() async throws {
        for pane in SettingsPane.available(showsAI: true, showsAIApps: true) {
            try await settings(pane)
        }
    }

    private func settings(_ pane: SettingsPane) async throws {
        for appearance in SnapshotAppearance.allCases {
            let app = try await SnapshotApp()
            defer { app.tearDown() }
            let content = SettingsPaneView(pane: pane)
                .frame(width: Metrics.settingsWidth, height: 520)
            let window = SnapshotWindow.open(
                app.withEnvironment(content),
                size: CGSize(width: Metrics.settingsWidth, height: 520),
                title: String(localized: pane.title),
                appearance: appearance,
                styleMask: [.titled, .closable]
            )
            defer { window.close() }
            try await SnapshotWindow.settle()
            try Snapshot.verify(try await SnapshotWindow.stableCapture(window), named: "settings-\(pane.rawValue).\(appearance.rawValue)")
        }
    }

    // MARK: Paywall

    /// The product comes from MindMapAI.storekit, as in the IAP review screenshot.
    @Test(.storeKitTestLock) func paywall() async throws {
        let url = try #require(Bundle(for: SnapshotApp.self).url(forResource: "MindMapAI", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.disableDialogs = true
        session.clearTransactions()
        for appearance in SnapshotAppearance.allCases {
            let app = try await SnapshotApp()
            defer { app.tearDown() }
            await app.pro.loadProduct()
            #expect(app.pro.product != nil)
            let window = SnapshotWindow.open(
                app.withEnvironment(PaywallView()),
                size: CGSize(width: Metrics.paywallWidth, height: 720),
                appearance: appearance,
                styleMask: [.titled, .closable]
            )
            defer { window.close() }
            try await SnapshotWindow.settle()
            try Snapshot.verify(try await SnapshotWindow.stableCapture(window), named: "paywall.\(appearance.rawValue)")
        }
    }
}

/// The app as the UI test mode starts it, for one snapshot: an in-memory store
/// with the `sample` fixture, a scripted AI that is ready, Pro not unlocked,
/// and preferences at their defaults whatever this Mac's app has stored.
@MainActor
final class SnapshotApp {
    let environment: AppEnvironment
    let provider = MockAIProvider()
    let pro = ProEntitlement(syncWithAppStore: {})
    let ai: AIService
    let sync: CloudSyncMonitor
    let defaults: UserDefaults
    /// The fixture's maps by title.
    private(set) var mapIDs: [String: MapID] = [:]
    private let suiteName = "MacSnapshotTests.\(UUID().uuidString)"
    private let savedArguments: [String: Any]
    private var windowToken = WindowToken()

    init() async throws {
        // The hosted tests share the real app's defaults. Values in the argument
        // domain win over stored ones and are never written, so every
        // `@AppStorage` reads the default here and nothing reaches the person's prefs.
        savedArguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        UserDefaults.standard.setVolatileDomain(
            savedArguments.merging(Self.defaultPreferences) { _, new in new },
            forName: UserDefaults.argumentDomain
        )
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.set(true, forKey: AIAssistant.privacyNoticeKey)

        let repository = try PersistenceController.makeRepository(at: .inMemory)
        let fixture = try UITestFixture.sample.makeMaps()
        for graph in Self.editedDaysAgo(fixture.graphs) {
            try await repository.create(graph)
            mapIDs[graph.map.title] = graph.map.id
        }
        for id in fixture.favorites {
            try await repository.setFavorite(true, for: id)
        }
        environment = AppEnvironment(repository: repository, spotlightIndex: NoSearchIndex())
        provider.setCapabilities(.readyForTesting)
        ai = AIService(provider: { [provider] in provider }, entitlements: pro, defaults: defaults)
        await ai.refresh()
        sync = CloudSyncMonitor(defaults: defaults, isEntitled: false, isUITest: true)
    }

    func tearDown() {
        UserDefaults.standard.setVolatileDomain(savedArguments, forName: UserDefaults.argumentDomain)
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// The defaults of every preference a Mac view reads.
    private static let defaultPreferences: [String: Any] = [
        AppearancePreference.storageKey: AppearancePreference.system.rawValue,
        NewMapPreferences.themeKey: MindMapTheme.standard.rawValue,
        ExportPreferences.includeNotesKey: true,
        ExportPreferences.imageScaleKey: ImageScale.double.rawValue,
        ExportPreferences.pageModeKey: PDFPageMode.singlePage.rawValue,
        ExportPreferences.paperKey: PaperSize.a4.rawValue,
        ExportPreferences.backgroundKey: ExportBackground.appearance.rawValue,
        VoiceInput.languageKey: VoiceLanguage.english.rawValue,
        AIService.enabledKey: true,
        AIAssistant.privacyNoticeKey: true,
        AIAppsHost.enabledKey: false,
        AIAppsHost.portKey: 51_947,
        CloudSyncMonitor.enabledKey: true,
    ]

    /// The `sample` maps of the UI test mode, edited a fixed number of days
    /// ago so the library's relative dates read the same on every run.
    private static func editedDaysAgo(_ graphs: [GraphState]) -> [GraphState] {
        graphs.enumerated().map { index, graph in
            var map = graph.map
            map.updatedAt = Date.now.addingTimeInterval(-Double(3 - index) * 86_400)
            return GraphState(map: map, nodes: graph.nodes.values, edges: graph.edges.values)
        }
    }

    func mapID(_ title: String) -> MapID? {
        mapIDs[title]
    }

    /// The fixture map's session, the one every window on it shares.
    func openMap(_ id: MapID) async throws -> OpenMap {
        guard case .ready(let map) = await environment.openMaps.open(id, in: windowToken, service: ai) else {
            throw OpenFailed()
        }
        return map
    }

    var root: some View {
        withEnvironment(RootView(environment: environment))
    }

    func withEnvironment(_ view: some View) -> some View {
        view
            .environment(pro)
            .environment(ai)
            .environment(sync)
            .environment(environment.aiApps)
    }

    private struct OpenFailed: Error {}
}
#endif

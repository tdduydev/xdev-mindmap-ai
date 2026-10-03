import AppIntents
import MindMapAIApple
import MindMapAICore
import MindMapDomain
import MindMapPersistence
import OSLog
import SwiftUI
import TipKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@main
struct MindMapAIApp: App {
    static let mainWindowID = "main"
    /// Windows that show one map each, opened with the map's ID (FR-LIB-10).
    static let mapWindowID = "map"

    @State private var launch: AppLaunch
    @State private var pro: ProEntitlement
    /// Shared by every window and Settings; the model itself loads on first use.
    @State private var ai: AIService
    @State private var sync: CloudSyncMonitor
    @State private var preferenceSync: PreferenceCloudSync
    @AppStorage(AppearancePreference.storageKey, store: AppDefaults.store) private var appearance = AppearancePreference.system
    @Environment(\.scenePhase) private var scenePhase

    /// Nil when the store did not open; Settings then shows AI Apps without a server.
    private var aiApps: AIAppsHost? {
        if case .ready(let environment) = launch { environment.aiApps } else { nil }
    }

    init() {
        let pro = ProEntitlement()
        _pro = State(initialValue: pro)
        let sync = CloudSyncMonitor()
        _sync = State(initialValue: sync)
        _preferenceSync = State(initialValue: PreferenceCloudSync(isEnabled: sync.storeSync != .off))
        let launch = AppEnvironment.live(sync: sync.storeSync)
        _launch = State(initialValue: launch)
        // The AI's Pro features ask the same entitlement as every other Pro
        // feature. The chat reads the library, so it needs the store.
        var chatProvider: (() -> any ChatProvider)?
        if case .ready(let environment) = launch {
            chatProvider = { AppleChatProvider(queries: environment.mapQueries) }
        }
        #if DEBUG
        if let mode = UITestMode.current?.ai, case .ready(let environment) = launch {
            _ai = State(initialValue: UITestAIService.make(mode, queries: environment.mapQueries, entitlements: pro))
        } else {
            _ai = State(initialValue: AIService(chatProvider: chatProvider, entitlements: pro))
        }
        #else
        _ai = State(initialValue: AIService(chatProvider: chatProvider, entitlements: pro))
        #endif
        // Before any view resolves a brand font by name.
        BrandFont.registerAll()
        if !UITestMode.isActive {
            do {
                try Tips.configure([.displayFrequency(.immediate)])
            } catch {
                Log.designSystem.error("Configuring tips failed: \(error.localizedDescription, privacy: .private)")
            }
        }
        #if os(iOS)
        // Transitions and keyboard animations too, which SwiftUI's Motion does not drive.
        if UITestMode.isActive { UIView.setAnimationsEnabled(false) }
        if UITestMode.current?.increasesContrast == true {
            // Scene traits reach every window, sheet and asset colour the way the
            // system setting does, so the accessibility audit sees the high-contrast colours.
            NotificationCenter.default.addObserver(forName: UIScene.willConnectNotification, object: nil, queue: .main) { notification in
                let scene = notification.object as? UIWindowScene
                MainActor.assumeIsolated { scene?.traitOverrides.accessibilityContrast = .high }
            }
        }
        #endif
        // Intents can run as soon as the app launches for them, before any window exists.
        if case .ready(let environment) = launch {
            let services = environment.intentServices()
            AppDependencyManager.shared.add(dependency: services)
            #if os(macOS)
            // AI apps reach the maps only while the app runs, and only on the Mac (ADR 0008).
            environment.aiApps.start()
            #endif
        }
    }

    var body: some Scene {
        WindowGroup(id: Self.mainWindowID) {
            Group {
                switch launch {
                case .ready(let environment):
                    RootView(environment: environment)
                case .failed:
                    StartupFailureView()
                }
            }
            .preferredColorScheme(appearance.colorScheme)
            .environment(pro)
            .task { await pro.start() }
            .environment(ai)
            .environment(sync)
            .task { sync.start() }
            .task { preferenceSync.start() }
            #if os(macOS)
            // A Mac window can stay in the active phase while another app is
            // in front, so coming back is caught from the app itself too.
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                Task { await pro.refresh() }
                sync.refreshAccount()
            }
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 760)        #endif
        .commands {
            MapCommands(ai: ai)
            // View ▸ Show/Hide Sidebar with ⌃⌘S, as the HIG lists for the View menu.
            SidebarCommands()
            // Show/Hide Inspector (⌃⌘I) in the View menu, driving each window's `.inspector`.
            InspectorCommands()
            FileTransferCommands()
            MapLinkCommands()
            RedeemCodeCommands(pro: pro)
            #if os(iOS)
            SettingsCommands()
            #endif
        }
        // A refund or a purchase on another device can change while the app is in the background.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await pro.refresh() }
                sync.refreshAccount()
            }
        }

        // SwiftUI keeps the map ID of each of these windows and opens them
        // again at relaunch; opening a map that has one brings it forward.
        WindowGroup(id: Self.mapWindowID, for: MapID.self) { $mapID in
            Group {
                if case .ready(let environment) = launch, let mapID {
                    MapWindowView(environment: environment, mapID: mapID)
                } else if case .failed = launch {
                    StartupFailureView()
                }
            }
            .preferredColorScheme(appearance.colorScheme)
            .environment(pro)
            .environment(ai)
            .environment(sync)
            // A restored map window can be the only window at launch.
            .task { sync.start() }
            .task { preferenceSync.start() }
        }
        #if os(macOS)
        .defaultSize(width: 980, height: 700)
        #endif

        #if os(macOS)
        Settings {
            SettingsView(environment: {
                if case .ready(let environment) = launch { return environment }
                return nil
            }(), showRecentlyDeleted: {
                NotificationCenter.default.post(name: .showRecentlyDeleted, object: nil)
            })
                .preferredColorScheme(appearance.colorScheme)
                .environment(pro)
                .environment(ai)
                .environment(sync)
                .environment(aiApps)
                .task { preferenceSync.start() }
        }
        #endif

        #if DEBUG && os(macOS)
        // Listed in the Window menu of debug builds only, for design review.
        Window(Text(verbatim: "Design System Gallery"), id: "design-system-gallery") {
            DesignSystemGallery()
        }
        #endif
    }
}

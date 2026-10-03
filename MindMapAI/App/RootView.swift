import MindMapAICore
import MindMapDomain
import MindMapPersistence
import MindMapQuery
import OSLog
import SwiftUI

/// Sidebar, library and editor. On a narrow iPhone the split view collapses
/// into a navigation stack by itself.
struct RootView: View {
    let environment: AppEnvironment
    @Environment(AIService.self) private var ai
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
    /// False on iPhone, which has one window.
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    @State private var router: AppRouter
    @State private var library: LibraryModel
    @State private var transfer: FileTransfer
    @State private var window = WindowToken()
    @State private var windowHandle = WindowHandle()
    @AppStorage("onboarding.completed", store: AppDefaults.store) private var onboardingCompleted = false
    @AppStorage("onboarding.introductionFinished", store: AppDefaults.store) private var introductionFinished = false
    @State private var showsOnboarding = false
    /// Ask About Library (MM-52): one conversation per library window.
    @State private var libraryChat: LibraryChat?
    /// What the window showed, brought back at relaunch (FR-PER-09).
    @SceneStorage("library.section") private var savedSection: LibrarySection = .all
    @SceneStorage("editor.map") private var savedMapID: String?
    @SceneStorage("editor.state") private var savedEditor: Data?

    init(environment: AppEnvironment) {
        self.environment = environment
        let router = AppRouter()
        let library = LibraryModel(repository: environment.repository, spotlightIndex: environment.spotlightIndex)
        _router = State(initialValue: router)
        _library = State(initialValue: library)
        _transfer = State(initialValue: FileTransfer(
            createMap: { await library.createMap($0, imageData: $1) },
            openMap: { router.selectedMapID = $0 }
        ))
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $router.section, environment: environment)
        } content: {
            LibraryView(
                model: library,
                section: router.section ?? .all,
                selection: mapSelection,
                openInNewWindow: mapWindowOpener
            )
            .modifier(LibraryChatPresenter(chat: libraryChat))
        } detail: {
            if let mapID = router.selectedMapID {
                EditorView(
                    mapID: mapID,
                    openMaps: environment.openMaps,
                    window: window,
                    restoration: editorRestoration,
                    generatesOnOpen: router.pendingMapGeneration == mapID,
                    onGenerationStarted: { router.pendingMapGeneration = nil }
                )
                .id(mapID)
            } else {
                ContentUnavailableView(
                    "No Map Selected",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("Choose a map, or start a new one.")
                )
            }
        }
        .windowHandle(windowHandle)
        .onAppear(perform: restoreWindow)
        .onAppear(perform: makeLibraryChat)
        .onDisappear {
            environment.openMaps.unregister(window)
            if showsOnboarding {
                environment.isPreparingOnboarding = false
                introductionFinished = true
            }
        }
        .onChange(of: router.section) { _, section in savedSection = section ?? .all }
        .onReceive(NotificationCenter.default.publisher(for: .showRecentlyDeleted)) { _ in
            router.section = .recentlyDeleted
        }
        .onChange(of: router.selectedMapID) { _, id in savedMapID = id?.description }
        .task {
            await environment.prepare()
            await library.load()
            // The first run can wait for iCloud for a while; the list keeps
            // following the store meanwhile, so maps arriving show at once.
            let onboarding = Task { await startOnboardingIfNeeded() }
            await library.observeChanges()
            onboarding.cancel()
        }
        .sheet(isPresented: $showsOnboarding) {
            OnboardingView {
                showsOnboarding = false
                introductionFinished = true
                environment.isPreparingOnboarding = false
            }
        }
        // FR-AI-01: Apple Intelligence can be turned on or off while the app is away.
        .task { await ai.refresh() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await ai.refresh() }
            // The Share Extension and the intents write to the same store.
            Task { await library.load() }
        }
        .onChange(of: environment.openRequests.pending, initial: true) { _, _ in
            openRequestedMap()
        }
        .focusedSceneValue(\.openInNewWindowAction, openSelectedMapInNewWindow)
        .focusedSceneValue(\.libraryChat, libraryChat)
        .focusedSceneValue(\.newMapWithAIAction, ai.showsControls ? NewMapAction(perform: createMapWithAI) : nil)
        .modifier(FileTransferPresenter(transfer: transfer, entitlements: ai.entitlements))
        .redeemCodeCommandTarget()
    }

    /// A map an intent or Spotlight asked for (FR-SYS-03, FR-SYS-04). The
    /// library reloads first: the intent may have just created the map.
    private func openRequestedMap() {
        guard let id = environment.openRequests.take() else { return }
        Task {
            await library.load()
            show(id)
        }
    }

    /// Joins the app's open maps and shows what the window showed before the
    /// app quit. A map deleted since shows Map Not Found, which says why.
    private func restoreWindow() {
        let handle = windowHandle
        environment.openMaps.register(window, activate: handle.activate, onMapChange: library.didChange)
        router.section = savedSection
        if router.selectedMapID == nil, let saved = savedMapID.flatMap(UUID.init(uuidString:)) {
            show(MapID(saved))
        }
    }

    /// A citation opens its map in this window, or brings forward the
    /// window that shows it, and selects the topic there.
    private func makeLibraryChat() {
        guard libraryChat == nil else { return }
        let queries = environment.mapQueries
        let openMaps = environment.openMaps
        libraryChat = LibraryChat(service: ai) { citation in
            let ref = TopicRef(mapID: citation.mapID, nodeID: citation.nodeID)
            guard (try? await queries.topic(ref)) != nil else { return false }
            openMaps.showTopic(citation.nodeID, in: citation.mapID)
            show(citation.mapID)
            return true
        }
    }

    /// The library's selection. Picking a map another window shows brings
    /// that window forward and leaves this one as it was (FR-PER-08).
    private var mapSelection: Binding<MapID?> {
        Binding(get: { router.selectedMapID }, set: { show($0) })
    }

    private func show(_ id: MapID?) {
        if let id, id != router.selectedMapID, environment.openMaps.activateWindow(showing: id, besides: window) {
            return
        }
        router.selectedMapID = id
    }

    /// A map in a window of its own (FR-LIB-10). This window lets go of it
    /// first, so the map is in one window.
    private func openInNewWindow(_ id: MapID) {
        if environment.openMaps.activateWindow(showing: id, besides: window) { return }
        if router.selectedMapID == id { router.selectedMapID = nil }
        openWindow(id: MindMapAIApp.mapWindowID, value: id)
    }

    private var mapWindowOpener: ((MapID) -> Void)? {
        guard supportsMultipleWindows else { return nil }
        return { openInNewWindow($0) }
    }

    private var openSelectedMapInNewWindow: OpenInNewWindowAction? {
        guard supportsMultipleWindows, let id = router.selectedMapID else { return nil }
        return OpenInNewWindowAction { openInNewWindow(id) }
    }

    private var editorRestoration: Binding<EditorRestoration?> {
        Binding(get: { EditorRestoration(data: savedEditor) }, set: { savedEditor = $0?.data })
    }

    /// A new map that opens on Generate Map (FR-AI-03).
    private func createMapWithAI() {
        Task {
            guard let id = await library.createMap(theme: NewMapPreferences.theme(entitlements: ai.entitlements)) else { return }
            router.pendingMapGeneration = id
            show(id)
        }
    }

    /// An existing library is also the upgrade marker: a person with maps
    /// must reach those maps without a first-run sheet or a duplicate sample.
    /// With iCloud on, `FirstRunGate` also asks the person's other devices.
    private func startOnboardingIfNeeded() async {
        guard library.failure == nil else { return }
        if environment.isPreparingOnboarding { return }
        let gate = firstRunGate
        if onboardingCompleted {
            // A previous launch may have closed while the introduction was up.
            introductionFinished = true
            // A device that finished before iCloud was on tells the others now.
            gate.recordCompleted()
            return
        }
        // Claim first launch before any await, since two fresh windows can
        // otherwise create two samples from the same empty store.
        environment.isPreparingOnboarding = true
        let decision = await gate.decide()
        // The window closed while waiting for iCloud: the next one decides.
        guard !Task.isCancelled else {
            environment.isPreparingOnboarding = false
            return
        }
        guard decision == .createSample else {
            onboardingCompleted = true
            introductionFinished = true
            environment.isPreparingOnboarding = false
            return
        }
        do {
            let sample = try SampleMap.make(languageCode: Locale.preferredLanguages.first ?? "en")
            guard let id = await library.createMap(sample) else {
                environment.isPreparingOnboarding = false
                return
            }
            onboardingCompleted = true
            gate.recordCompleted()
            show(id)
            showsOnboarding = true
        } catch {
            environment.isPreparingOnboarding = false
            Log.persistence.error("Creating the sample map failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    private var firstRunGate: FirstRunGate {
        let library = library
        let storeSync = environment.storeSync
        let firstImport = environment.firstImport
        return FirstRunGate(
            isCloudStoreOn: storeSync != .off,
            cloudFlag: UbiquitousFirstRunFlag(),
            accountStatus: { await CloudSyncMonitor.account(for: storeSync) },
            waitForFirstImport: { flag in
                if await !firstImport.wait(for: flag) {
                    Log.persistence.notice("No iCloud import within the first-run wait")
                }
            },
            libraryHasMaps: { await library.reloadHasAnyMap() }
        )
    }
}

struct StartupFailureView: View {
    var body: some View {
        ContentUnavailableView {
            // The small mark says which app this is when no other window is open.
            VStack(spacing: Spacing.md) {
                BrandMark(style: .icon, size: .small)
                Label("Can’t Open Your Maps", systemImage: "externaldrive.badge.exclamationmark")
            }
        } description: {
            Text("MindMap AI couldn’t open its storage. Restart the app. If it keeps happening, contact xDev support.")
        } actions: {
            Link("Contact Support", destination: AppLinks.support)
        }
    }
}

/// The library chat's panel beside the library list (a sheet on iPhone), its
/// toolbar button, the paywall and the on-device notice. Nothing while the
/// window has not made the chat yet.
private struct LibraryChatPresenter: ViewModifier {
    let chat: LibraryChat?

    func body(content: Content) -> some View {
        if let chat {
            content.modifier(Presenter(chat: chat))
        } else {
            content
        }
    }

    private struct Presenter: ViewModifier {
        @Bindable var chat: LibraryChat

        func body(content: Content) -> some View {
            content
                .inspector(isPresented: $chat.isPresented) {
                    LibraryChatPanel(chat: chat)
                }
                .toolbar {
                    if chat.showsEntryPoints {
                        ToolbarItem {
                            Button(action: chat.toggle) {
                                Label("Ask About Library", systemImage: "books.vertical")
                            }
                            .help(chat.isPresented ? Text("Hide Chat") : Text("Ask About Library"))
                            .accessibilityIdentifier(AccessibilityID.LibraryChat.toolbar)
                        }
                    }
                }
                .proChoicePaywall($chat.paywall)
                .sheet(isPresented: $chat.isShowingPrivacyNotice, onDismiss: chat.declinePrivacyNotice) {
                    AIPrivacyNotice(onContinue: chat.acknowledgePrivacyNotice, onCancel: chat.declinePrivacyNotice)
                        #if os(macOS)
                        .frame(width: Metrics.aiSheetWidth)
                        #endif
                }
        }
    }
}

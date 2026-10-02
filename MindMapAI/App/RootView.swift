import SwiftUI

/// Sidebar, library and editor. On a narrow iPhone the split view collapses
/// into a navigation stack by itself.
struct RootView: View {
    let environment: AppEnvironment
    @Environment(AIService.self) private var ai
    @Environment(\.scenePhase) private var scenePhase
    @State private var router: AppRouter
    @State private var library: LibraryModel
    @State private var transfer: FileTransfer

    init(environment: AppEnvironment) {
        self.environment = environment
        let router = AppRouter()
        let library = LibraryModel(repository: environment.repository, spotlightIndex: environment.spotlightIndex)
        _router = State(initialValue: router)
        _library = State(initialValue: library)
        _transfer = State(initialValue: FileTransfer(
            createMap: { await library.createMap($0) },
            openMap: { router.selectedMapID = $0 }
        ))
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $router.section)
        } content: {
            LibraryView(model: library, section: router.section ?? .all, selection: $router.selectedMapID)
        } detail: {
            if let mapID = router.selectedMapID {
                EditorView(
                    mapID: mapID,
                    repository: environment.repository,
                    onMapChange: library.didChange,
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
        .task {
            await environment.prepare()
            await library.observeChanges()
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
        .focusedSceneValue(\.newMapWithAIAction, ai.showsEntryPoints ? NewMapAction(perform: createMapWithAI) : nil)
        .modifier(FileTransferPresenter(transfer: transfer, entitlements: ai.entitlements))
    }

    /// A map an intent or Spotlight asked for (FR-SYS-03, FR-SYS-04). The
    /// library reloads first: the intent may have just created the map.
    private func openRequestedMap() {
        guard let id = environment.openRequests.take() else { return }
        Task {
            await library.load()
            router.selectedMapID = id
        }
    }

    /// A new map that opens on Generate Map (FR-AI-03).
    private func createMapWithAI() {
        Task {
            guard let id = await library.createMap() else { return }
            router.pendingMapGeneration = id
            router.selectedMapID = id
        }
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

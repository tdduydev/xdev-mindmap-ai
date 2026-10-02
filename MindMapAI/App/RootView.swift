import SwiftUI

/// Sidebar, library and editor. On a narrow iPhone the split view collapses
/// into a navigation stack by itself.
struct RootView: View {
    let environment: AppEnvironment
    @State private var router = AppRouter()
    @State private var library: LibraryModel

    init(environment: AppEnvironment) {
        self.environment = environment
        _library = State(initialValue: LibraryModel(repository: environment.repository))
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $router.section)
        } content: {
            LibraryView(model: library, section: router.section ?? .all, selection: $router.selectedMapID)
        } detail: {
            if let mapID = router.selectedMapID {
                EditorView(mapID: mapID, repository: environment.repository, onMapChange: library.didChange)
                    .id(mapID)
            } else {
                ContentUnavailableView(
                    "No Map Selected",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("Choose a map, or start a new one.")
                )
            }
        }
        .task { await library.load() }
    }
}

struct StartupFailureView: View {
    var body: some View {
        ContentUnavailableView(
            "Can’t Open Your Maps",
            systemImage: "externaldrive.badge.exclamationmark",
            description: Text("MindMap AI couldn’t open its storage. Restart the app. If it keeps happening, contact xDev support.")
        )
    }
}

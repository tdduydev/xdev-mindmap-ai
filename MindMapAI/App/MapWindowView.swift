import MindMapDomain
import MindMapGraph
import MindMapIntents
import MindMapPersistence
import OSLog
import SwiftUI

/// A window that shows one map, without the library (FR-LIB-10): on iPad one
/// per map in Stage Manager, on the Mac from Open in New Window. Its map
/// comes from `OpenMaps` like any other window's.
struct MapWindowView: View {
    let environment: AppEnvironment
    let mapID: MapID
    @Environment(AIService.self) private var ai
    @Environment(\.openWindow) private var openWindow
    @State private var window = WindowToken()
    @State private var windowHandle = WindowHandle()
    @State private var transfer: FileTransfer?
    @SceneStorage("editor.state") private var savedEditor: Data?

    var body: some View {
        NavigationStack {
            EditorView(
                mapID: mapID,
                openMaps: environment.openMaps,
                window: window,
                restoration: Binding(get: { EditorRestoration(data: savedEditor) }, set: { savedEditor = $0?.data })
            )
        }
        .windowHandle(windowHandle)
        .onAppear {
            let handle = windowHandle
            // No library here; the other windows' libraries hear of changes through the store.
            environment.openMaps.register(window, activate: handle.activate, onMapChange: { _ in })
            if transfer == nil { transfer = makeTransfer() }
        }
        .onDisappear { environment.openMaps.unregister(window) }
        .modifier(OptionalFileTransfer(transfer: transfer, entitlements: ai.entitlements))
    }

    /// Import and Export as in the main window; a map imported as a new map
    /// opens in a window of its own.
    private func makeTransfer() -> FileTransfer {
        let environment = environment
        let openWindow = openWindow
        return FileTransfer(
            createMap: { graph in
                do {
                    try await environment.repository.create(graph)
                    await environment.spotlightIndex.update(graph.map)
                    return graph.map.id
                } catch {
                    Log.persistence.error("Creating a map failed: \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            },
            openMap: { openWindow(id: MindMapAIApp.mapWindowID, value: $0) }
        )
    }
}

private struct OptionalFileTransfer: ViewModifier {
    let transfer: FileTransfer?
    let entitlements: any ProEntitlements

    func body(content: Content) -> some View {
        if let transfer {
            content.modifier(FileTransferPresenter(transfer: transfer, entitlements: entitlements))
        } else {
            content
        }
    }
}

import MindMapDomain
import MindMapPersistence
import SwiftUI

/// Opens a map and shows its editor once it is loaded.
struct EditorView: View {
    let mapID: MapID
    let repository: any MapRepository
    let onMapChange: (MindMap) -> Void
    @State private var opening: EditorSession.Opening?
    /// Made once per opened map, so the camera survives switching to the outline and back.
    @State private var canvas: CanvasModel?

    var body: some View {
        Group {
            switch opening {
            case nil:
                ProgressView()
            case .ready(let session):
                if let canvas {
                    MapEditorView(session: session, canvas: canvas)
                }
            case .missing:
                ContentUnavailableView(
                    "Map Not Found",
                    systemImage: "questionmark.folder",
                    description: Text("It may have been deleted on another device.")
                )
            case .failed:
                ContentUnavailableView(
                    "Couldn’t Open Map",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Try again. If it keeps happening, restart the app.")
                )
            }
        }
        .task {
            let opened = await EditorSession.open(mapID: mapID, repository: repository, onMapChange: onMapChange)
            if case .ready(let session) = opened { canvas = CanvasModel(session: session) }
            opening = opened
        }
    }
}

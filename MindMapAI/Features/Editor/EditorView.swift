import MindMapCapture
import MindMapDomain
import MindMapPersistence
import SwiftUI

/// Opens a map and shows its editor once it is loaded. The map comes from
/// `OpenMaps`, so a map shown in two windows is one session (FR-PER-08).
struct EditorView: View {
    let mapID: MapID
    let openMaps: OpenMaps
    let window: WindowToken
    /// The window's saved editor state: restored once the map opens, then kept up to date (FR-PER-09).
    @Binding var restoration: EditorRestoration?
    /// Opens the Generate Map sheet once the map is loaded (New Map with AI).
    var generatesOnOpen = false
    var onGenerationStarted: () -> Void = {}
    @Environment(AIService.self) private var ai
    @Environment(\.undoManager) private var undoManager
    @State private var opening: OpenMaps.Opening?
    /// Voice input belongs to this window: its microphone and sheet are not shared
    /// with another window showing the same map, while the topics it adds are.
    @State private var voice: VoiceInput?

    var body: some View {
        Group {
            switch opening {
            case nil:
                ProgressView()
            case .ready(let map):
                if let gone = map.session.removedElsewhere {
                    // Deleted on another device while open here (FR-SYN-04).
                    Self.unavailable(gone == .deleted ? .missing : .recentlyDeleted)
                } else if let voice {
                    MapEditorView(session: map.session, canvas: map.canvas, assistant: map.assistant, chat: map.chat, voice: voice)
                        .onChange(of: EditorRestoration(map.session)) { _, state in
                            restoration = state
                        }
                }
            case .missing:
                Self.unavailable(.missing)
            case .recentlyDeleted:
                Self.unavailable(.recentlyDeleted)
            case .failed:
                Self.unavailable(.failed)
            }
        }
        .task {
            let opened = await openMaps.open(mapID, in: window, service: ai)
            if case .ready(let map) = opened {
                restoration?.apply(to: map.session)
                restoration = EditorRestoration(map.session)
                voice = VoiceInput(session: map.session, transcriber: AppleSpeechTranscriber(), entitlements: ai.entitlements)
                if generatesOnOpen {
                    onGenerationStarted()
                    map.assistant.requestGenerateMap()
                }
            }
            opening = opened
        }
        .onDisappear {
            if case .ready(let map) = opening {
                // This window's ⌘Z must not reach a map it no longer shows,
                // which may now be in another window.
                if let undoManager {
                    undoManager.removeAllActions(withTarget: map.session)
                    if map.session.undoManager === undoManager { map.session.undoManager = nil }
                }
            }
            openMaps.close(mapID, in: window)
        }
    }

    private enum Unavailable {
        case missing, recentlyDeleted, failed
    }

    @ViewBuilder
    private static func unavailable(_ reason: Unavailable) -> some View {
        switch reason {
        case .missing:
            ContentUnavailableView(
                "Map Not Found",
                systemImage: "questionmark.folder",
                description: Text("It may have been deleted on another device.")
            )
        case .recentlyDeleted:
            ContentUnavailableView(
                "Map in Recently Deleted",
                systemImage: "trash",
                description: Text("Restore it from Recently Deleted to open it.")
            )
        case .failed:
            ContentUnavailableView(
                "Couldn’t Open Map",
                systemImage: "exclamationmark.triangle",
                description: Text("Try again. If it keeps happening, restart the app.")
            )
        }
    }
}

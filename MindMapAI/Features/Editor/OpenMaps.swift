import Foundation
import MindMapDomain
import MindMapPersistence
import Observation

/// A window, as `OpenMaps` knows it. Made by the window's root view, which
/// registers how to bring the window to the front.
struct WindowToken: Hashable {
    let id = UUID()
}

/// One map open in the app: its session, canvas and AI side, shared by every
/// window that shows the map.
@MainActor
final class OpenMap {
    let session: EditorSession
    let canvas: CanvasModel
    let assistant: AIAssistant

    init(session: EditorSession, assistant: AIAssistant) {
        self.session = session
        self.assistant = assistant
        canvas = CanvasModel(session: session, assistant: assistant)
    }
}

/// The maps open in the app, one `OpenMap` per map whatever the number of
/// windows showing it (FR-PER-08, NFR-REL-06).
///
/// Each session saves the change sets of its own engine. Two sessions on the
/// same map would each save from a graph the other has not seen, and the later
/// save would undo the earlier one in the store. With one session per map
/// there is one engine and one save queue, so no window can write over another.
///
/// It also keeps one window per map in the interface: a window that asks for a
/// map another window shows brings that window to the front instead
/// (`window(showing:besides:)`), as Mac document apps do.
@MainActor
@Observable
final class OpenMaps {
    enum Opening {
        case ready(OpenMap)
        case missing
        case failed
    }

    @ObservationIgnored private let repository: any MapRepository
    @ObservationIgnored private let clipboard: any TextClipboard
    @ObservationIgnored private var maps: [MapID: OpenMap] = [:]
    /// Opens in flight, so two windows restored at once share one load.
    @ObservationIgnored private var loading: [MapID: Task<Opening, Never>] = [:]
    /// Which windows show each map; a map leaves `maps` when none does and its saves are done.
    private var viewers: [MapID: [WindowToken]] = [:]
    @ObservationIgnored private var activators: [WindowToken: () -> Void] = [:]
    @ObservationIgnored private var mapChangeObservers: [WindowToken: (MindMap) -> Void] = [:]
    @ObservationIgnored private var closing: [MapID: Task<Void, Never>] = [:]

    init(repository: any MapRepository, clipboard: any TextClipboard = SystemClipboard()) {
        self.repository = repository
        self.clipboard = clipboard
    }

    // MARK: Windows

    /// Registers a window: how to bring it to the front, and its library's
    /// listener for map changes, which every session reports to.
    func register(_ window: WindowToken, activate: @escaping () -> Void, onMapChange: @escaping (MindMap) -> Void) {
        activators[window] = activate
        mapChangeObservers[window] = onMapChange
    }

    func unregister(_ window: WindowToken) {
        activators[window] = nil
        mapChangeObservers[window] = nil
    }

    /// Another window that shows `mapID`, if any.
    func window(showing mapID: MapID, besides window: WindowToken) -> WindowToken? {
        viewers[mapID]?.first { $0 != window }
    }

    /// Brings the window that shows `mapID` to the front, if another window
    /// shows it. Returns whether it did.
    @discardableResult
    func activateWindow(showing mapID: MapID, besides window: WindowToken) -> Bool {
        guard let other = self.window(showing: mapID, besides: window), let activate = activators[other] else { return false }
        activate()
        return true
    }

    // MARK: Opening and closing

    /// The open map for `mapID`, loading it if no window has it open. The
    /// window shows it until it calls `close`.
    func open(_ mapID: MapID, in window: WindowToken, service: AIService) async -> Opening {
        viewers[mapID, default: []].append(window)
        let opening = await load(mapID, service: service)
        if case .ready = opening {
            // The window may have closed it while it loaded.
            releaseIfUnused(mapID)
        } else {
            removeViewer(window, of: mapID)
        }
        return opening
    }

    /// The window no longer shows `mapID`. Once no window does, the map stays
    /// until its last save is done, so opening it again meanwhile gets the same
    /// session rather than a load that misses those saves.
    func close(_ mapID: MapID, in window: WindowToken) {
        removeViewer(window, of: mapID)
        releaseIfUnused(mapID)
    }

    private func releaseIfUnused(_ mapID: MapID) {
        guard viewers[mapID] == nil, let map = maps[mapID], closing[mapID] == nil else { return }
        closing[mapID] = Task {
            await map.session.flush()
            closing[mapID] = nil
            // Opened again while saving: keep it.
            if viewers[mapID] == nil { maps[mapID] = nil }
        }
    }

    /// Waits for every open map's saves, for tests and before quitting.
    func flush() async {
        for map in maps.values { await map.session.flush() }
        for task in closing.values { await task.value }
    }

    /// Whether `mapID` is loaded, for tests.
    func isOpen(_ mapID: MapID) -> Bool { maps[mapID] != nil }

    private func removeViewer(_ window: WindowToken, of mapID: MapID) {
        guard var windows = viewers[mapID], let index = windows.firstIndex(of: window) else { return }
        windows.remove(at: index)
        viewers[mapID] = windows.isEmpty ? nil : windows
    }

    private func load(_ mapID: MapID, service: AIService) async -> Opening {
        if let map = maps[mapID] { return .ready(map) }
        if let task = loading[mapID] { return await task.value }
        let task = Task { [weak self, repository, clipboard] () -> Opening in
            let opened = await EditorSession.open(mapID: mapID, repository: repository, clipboard: clipboard) { [weak self] map in
                self?.mapDidChange(map)
            }
            switch opened {
            case .ready(let session):
                return .ready(OpenMap(session: session, assistant: AIAssistant(session: session, service: service)))
            case .missing: return .missing
            case .failed: return .failed
            }
        }
        loading[mapID] = task
        let opening = await task.value
        loading[mapID] = nil
        if case .ready(let map) = opening { maps[mapID] = map }
        return opening
    }

    private func mapDidChange(_ map: MindMap) {
        for observer in mapChangeObservers.values { observer(map) }
    }
}

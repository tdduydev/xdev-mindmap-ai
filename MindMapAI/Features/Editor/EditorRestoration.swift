import Foundation
import MindMapDomain
import MindMapGraph
import MindMapSearch

/// What a window brings back of its editor at relaunch (FR-PER-09): the
/// selection, canvas or outline, and the filter and focus (MM-36). Topic and
/// tag IDs only, never map content, as it is kept in the system's window
/// state, so the filter's text is left out. Device-local: never synced.
struct EditorRestoration: Codable, Equatable {
    var mapID: MapID
    var selectedIDs: [NodeID]
    var primary: NodeID?
    var presentation: EditorPresentation
    // Optional, so window state saved before MM-36 still reads.
    var filter: MapFilter?
    var filterMode: FilterMode?
    var isFilterBarShown: Bool?
    var focusID: NodeID?

    init(_ session: EditorSession) {
        mapID = session.map.id
        // Sorted, so the same selection always encodes the same and does not
        // count as a change.
        selectedIDs = session.selectedIDs.sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
        primary = session.primarySelection
        presentation = session.presentation
        var filter = session.filter
        filter.text = ""
        self.filter = filter.isActive ? filter : nil
        filterMode = session.filterMode
        isFilterBarShown = session.isFilterBarShown
        focusID = session.focusID
    }

    /// Topics deleted since, here or on another device, are left out; with
    /// none left the session keeps its own selection.
    func apply(to session: EditorSession) {
        // The window showed another map before.
        guard session.map.id == mapID else { return }
        let state = session.engine.state
        session.presentation = presentation
        if var filter {
            // Tags deleted since match nothing; leaving them would filter out every topic.
            filter.tagIDs = filter.tagIDs.filter { state.tags[$0] != nil }
            session.filter = filter
        }
        if let filterMode { session.filterMode = filterMode }
        if let isFilterBarShown { session.isFilterBarShown = isFilterBarShown }
        if let focusID, state.node(focusID) != nil { session.focus(on: focusID) }
        let ids = Set(selectedIDs.filter { state.node($0) != nil })
        guard !ids.isEmpty else { return }
        session.setSelection(ids, primary: primary.flatMap { ids.contains($0) ? $0 : nil })
    }

    /// For `@SceneStorage`, which keeps `Data`. Unreadable data (from another
    /// version) is no state rather than an error.
    init?(data: Data?) {
        guard let data, let state = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        self = state
    }

    var data: Data? { try? JSONEncoder().encode(self) }
}

extension EditorPresentation: Codable {}

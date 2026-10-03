import Foundation
import MindMapDomain
import MindMapGraph
import MindMapSearch

/// Filter bar and Focus on Branch (MM-36, [[node-organization]]).
///
/// What actions reach under a filter: Select All and the rectangle pick only
/// topics that are shown and match, and tag, colour, symbol and task actions
/// apply to the selection only, so they never touch hidden topics. Branch
/// actions (delete, cut, copy, duplicate, move) take the whole branch, hidden
/// topics included, as they do for a collapsed branch.
extension EditorSession {
    /// Whether the canvas and outline draw less than the whole map.
    var isViewFiltered: Bool { filter.isActive || focusID != nil }

    /// What this window shows; computed per read from the current map.
    var filterView: MapFilterView {
        MapFilterView(state: engine.state, filter: filter, mode: filterMode, focusID: focusID, today: .today())
    }

    /// For the filter bar and the chip: matching topics, and all topics in scope.
    var filterCounts: (matches: Int, total: Int) {
        let view = filterView
        let total = view.focusID.map { engine.state.descendants(of: $0).count + 1 } ?? engine.state.nodes.count
        return (view.matches.count, total)
    }

    func toggleFilterBar() {
        isFilterBarShown.toggle()
    }

    /// View ▸ Clear Filter: every criterion goes; focus stays, it has its own exit.
    func clearFilter() {
        filter = MapFilter()
    }

    /// Adds a choice to one criterion, or takes it out.
    func toggleFilter<Value: Hashable>(_ value: Value, in criterion: WritableKeyPath<MapFilter, Set<Value>>) {
        if filter[keyPath: criterion].contains(value) {
            filter[keyPath: criterion].remove(value)
        } else {
            filter[keyPath: criterion].insert(value)
        }
    }

    // MARK: Focus on Branch

    var canFocusOnBranch: Bool {
        focusID != nil || selection.map { engine.state.node($0) != nil } == true
    }

    /// View ▸ Focus on Branch (⇧⌘F) on the selected topic; again exits.
    func toggleFocus() {
        if focusID != nil {
            exitFocus()
        } else if let selection {
            focus(on: selection)
        }
    }

    func focus(on id: NodeID) {
        guard engine.state.node(id) != nil else { return }
        // Focusing the central topic is the whole map.
        focusID = id == rootID ? nil : id
        selection = id
    }

    func exitFocus() {
        focusID = nil
    }

    /// The breadcrumb: central topic first, the focused topic last.
    var focusPath: [MindNode] {
        guard let focusID else { return [] }
        let state = engine.state
        return (state.ancestors(of: focusID).reversed() + [focusID]).compactMap { state.node($0) }
    }

    /// Focus ends when its topic goes: deleted, undone or removed by sync.
    func endFocusIfGone() {
        if let focusID, engine.state.node(focusID) == nil { self.focusID = nil }
    }

    /// The filter or focus changed: lay out again, recount Find, and keep the
    /// selection on something the window shows.
    func viewFilterDidChange() {
        onViewFilterChange?()
        if !findText.isEmpty { updateFind(selectingFirst: false) }
        guard isViewFiltered else { return }
        let view = filterView
        let kept = selectedIDs.filter(view.shown.contains)
        if kept.isEmpty {
            selection = view.focusID ?? rootID
        } else if kept != selectedIDs {
            setSelection(kept, primary: primarySelection.flatMap { kept.contains($0) ? $0 : nil })
        }
    }
}

import Foundation
import MindMapDomain
import MindMapGraph

// Boundaries (MM-37): a frame around one branch or a run of adjacent
// siblings. The run is positional, so the core keeps it valid as topics move;
// this file only turns the selection into commands.
extension EditorSession {
    var activeBoundary: GroupID? {
        guard selectedIDs.isEmpty, let selectedBoundary, engine.state.group(selectedBoundary)?.kind == .boundary else { return nil }
        return selectedBoundary
    }

    /// Selects one boundary and no topic or connection.
    func selectBoundary(_ id: GroupID?) {
        if id != nil {
            setSelection([], primary: nil)
            selectConnection(nil)
        }
        selectedBoundary = id
    }

    /// The selected topics as a run of adjacent siblings, first to last; one
    /// topic is a run of one. Nil for the central topic, a floating topic,
    /// topics under different parents, or a run with a gap.
    var selectedRun: (first: NodeID, last: NodeID)? {
        let state = engine.state
        guard let primary = selection, let parentID = state.node(primary)?.parentID else { return nil }
        let siblings = state.runSiblingIDs(of: parentID)
        let positions = selectedIDs.compactMap { id in state.node(id)?.parentID == parentID ? siblings.firstIndex(of: id) : nil }
        guard positions.count == selectedIDs.count, let low = positions.min(), let high = positions.max(),
              high - low + 1 == positions.count else { return nil }
        return (siblings[low], siblings[high])
    }

    /// The boundary framing exactly the selected run, if there is one.
    var boundaryAroundSelection: GroupID? {
        guard let run = selectedRun, let parentID = engine.state.node(run.first)?.parentID else { return nil }
        return engine.state.groups(under: parentID).first {
            $0.kind == .boundary && $0.firstNodeID == run.first && $0.lastNodeID == run.last
        }?.id
    }

    /// Topic ▸ Add Boundary / Remove Boundary (⌥⌘B) acts on a selected
    /// boundary, then on one framing the selection exactly.
    var boundaryToRemove: GroupID? { activeBoundary ?? boundaryAroundSelection }

    var canAddBoundary: Bool { boundaryToRemove == nil && selectedRun != nil }

    func toggleBoundary() {
        if let id = boundaryToRemove { return removeBoundary(id) }
        addBoundary()
    }

    /// Frames the selected run and selects the new boundary, so its title and
    /// colour can be set next. A run that would cross another boundary is
    /// refused by the command and nothing happens.
    func addBoundary() {
        guard canAddBoundary, let run = selectedRun else { return }
        let id = GroupID()
        if perform(AddGroupCommand(groupID: id, from: run.first, to: run.last), named: String(localized: "Add Boundary")) {
            selectBoundary(id)
        }
    }

    /// One step named "Rename Boundary"; blank removes the title.
    func renameBoundary(_ id: GroupID, to title: String) {
        guard let group = engine.state.group(id) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let new = trimmed.isEmpty ? nil : trimmed
        guard group.title != new else { return }
        perform(UpdateGroupCommand(groupID: id, title: .set(new)), named: String(localized: "Rename Boundary"))
    }

    /// Nil is the default colour, graphite.
    func setBoundaryColor(_ color: TopicColor?, for id: GroupID) {
        guard let group = engine.state.group(id), group.color != color else { return }
        perform(UpdateGroupCommand(groupID: id, color: .set(color)), named: String(localized: "Boundary Color"))
    }

    func removeBoundary(_ id: GroupID) {
        guard engine.state.group(id) != nil else { return }
        perform(RemoveGroupCommand(groupID: id), named: String(localized: "Remove Boundary"))
        if selectedBoundary == id { selectedBoundary = nil }
    }

    /// The members' titles, for VoiceOver and the inspector: "Design to Launch".
    func boundaryRangeTitle(_ id: GroupID) -> String? {
        guard let group = engine.state.group(id), let members = engine.state.members(of: group),
              let first = members.first.flatMap(engine.state.node), let last = members.last.flatMap(engine.state.node)
        else { return nil }
        let firstTitle = first.title.isEmpty ? String(localized: "Untitled Topic") : first.title
        let lastTitle = last.title.isEmpty ? String(localized: "Untitled Topic") : last.title
        return first.id == last.id ? firstTitle : String(localized: "\(firstTitle) to \(lastTitle)")
    }
}

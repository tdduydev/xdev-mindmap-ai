import Foundation
import MindMapDomain
import MindMapGraph

// Summaries (MM-65, FR-ORG-29): a bracket beyond a run of adjacent siblings
// and a summary topic beyond it. The run follows the boundary rules, which the
// core keeps; this file only turns the selection into commands.
extension EditorSession {
    /// The summary whose topic is the only selected topic: what Remove Summary
    /// acts on first, since the summary topic stands for its bracket.
    var summaryOfSelectedTopic: GroupID? {
        guard selectedIDs.count == 1, let selection else { return nil }
        return engine.state.summaries(naming: selection).first?.id
    }

    /// The summary bracketing exactly the selected run, if there is one.
    var summaryOverSelection: GroupID? {
        guard let run = selectedRun, let parentID = engine.state.node(run.first)?.parentID else { return nil }
        return engine.state.groups(under: parentID).first {
            $0.kind == .summary && $0.firstNodeID == run.first && $0.lastNodeID == run.last
        }?.id
    }

    /// Topic ▸ Add Summary / Remove Summary (⌥⌘]) removes the summary of a
    /// selected summary topic, then one over the selection exactly.
    var summaryToRemove: GroupID? { summaryOfSelectedTopic ?? summaryOverSelection }

    var canAddSummary: Bool {
        guard summaryToRemove == nil, let run = selectedRun else { return false }
        return AddSummaryCommand.canSummarize(from: run.first, to: run.last, in: engine.state)
    }

    func toggleSummary() {
        if let id = summaryToRemove { return removeSummary(id) }
        addSummary()
    }

    /// Brackets the selected run and starts typing in the new summary topic.
    func addSummary() {
        guard canAddSummary, let run = selectedRun else { return }
        let topicID = NodeID()
        let command = AddSummaryCommand(nodeID: topicID, from: run.first, to: run.last)
        if perform(command, named: String(localized: "Add Summary")) {
            selection = topicID
            focusRequest = topicID
        }
    }

    /// Takes the bracket and the summary topic's branch in one step.
    func removeSummary(_ id: GroupID) {
        guard engine.state.group(id)?.kind == .summary else { return }
        perform(RemoveSummaryCommand(groupID: id), named: String(localized: "Remove Summary"))
    }

    /// Whether a live summary shows this topic beyond its bracket.
    func isSummaryTopic(_ id: NodeID) -> Bool {
        guard let parentID = engine.state.node(id)?.parentID else { return false }
        return engine.state.summaryTopicIDs(under: parentID).contains(id)
    }

    /// "Summary of Design to Launch" for VoiceOver; nil for other topics.
    func summaryDescription(of id: NodeID) -> String? {
        guard let group = engine.state.summaries(naming: id).first,
              let members = engine.state.members(of: group) else { return nil }
        return Self.summaryDescription(members: members.compactMap { engine.state.node($0)?.title })
    }

    nonisolated static func summaryDescription(members: [String]) -> String? {
        let titles = members.map { $0.isEmpty ? String(localized: "Untitled Topic") : $0 }
        guard let first = titles.first, let last = titles.last else { return nil }
        return titles.count == 1
            ? String(localized: "Summary of \(first)")
            : String(localized: "Summary of \(first) to \(last)")
    }
}

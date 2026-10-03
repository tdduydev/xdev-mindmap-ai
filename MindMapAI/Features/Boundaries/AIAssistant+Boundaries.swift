import Foundation
import MindMapAICore
import MindMapDomain
import MindMapGraph
import SwiftUI

// Suggest Groups and Summarize Boundary (MM-37). The answer is a preview the
// canvas draws in the AI style; titles can be edited before Accept, and
// Accept is one command and one undo step.
extension AIAssistant {
    /// The selected boundary, or the one framing the selected topics exactly.
    func boundaryTarget() -> GroupID? {
        session.boundaryToRemove
    }

    /// Groups the children of the topic (the selection when nil).
    func suggestGroups(_ nodeID: NodeID? = nil) {
        guard canRun(.suggestGroups, on: nodeID), let id = target(nodeID) else { return }
        afterNotice { [weak self] in
            guard let self else { return }
            guard let request = SuggestGroupsRequest.make(
                for: id, in: self.session.engine.state, language: self.language(for: id), userLocaleIdentifier: self.locale.identifier
            ) else { return self.show(.topicGone) }
            let provider = self.service.provider
            self.clearAllSuggestionsForBoundaries()
            self.run(.suggestGroups) {
                try await provider.suggestGroups(request)
            } done: { [weak self] result in
                self?.showBoundarySuggestions(BoundarySuggestionState(result))
            }
        }
    }

    /// A title for the selected boundary.
    func summarizeBoundary() {
        guard canRun(.summarizeBoundary), let id = boundaryTarget(),
              let parent = session.engine.state.group(id)?.parentNodeID else { return }
        afterNotice { [weak self] in
            guard let self else { return }
            guard let request = SummarizeBoundaryRequest.make(
                for: id, in: self.session.engine.state, language: self.language(for: parent), userLocaleIdentifier: self.locale.identifier
            ) else { return self.show(.topicGone) }
            let provider = self.service.provider
            self.clearAllSuggestionsForBoundaries()
            self.run(.summarizeBoundary) {
                try await provider.summarizeBoundary(request)
            } done: { [weak self] result in
                self?.showBoundarySuggestions(BoundarySuggestionState(result))
            }
        }
    }

    /// The map as Accept would leave it, and the boundaries to draw as AI.
    func boundaryPreview() -> (state: GraphState, boundaries: Set<GroupID>)? {
        boundarySuggestions?.preview(in: session.engine)
    }

    /// How many topics Accept would move, for the suggestion bar.
    var boundarySuggestionMoves: Int {
        boundarySuggestions?.movedCount(in: session.engine.state) ?? 0
    }

    func renameBoundarySuggestion(_ id: GroupID, to title: String) {
        boundarySuggestions?.rename(id, to: title)
        onSuggestionsChange?()
    }

    func discardBoundarySuggestion(_ id: GroupID) {
        boundarySuggestions?.remove(id)
        if boundarySuggestions?.isEmpty == true { clearBoundarySuggestions() } else { onSuggestionsChange?() }
    }

    /// "Add AI Groups" or "Rename Boundary", one undo step.
    func acceptBoundarySuggestions() {
        guard var state = boundarySuggestions else { return }
        state.prune(in: session.engine.state)
        let name = state.kind == .title ? String(localized: "Rename Boundary") : String(localized: "Add AI Groups")
        do {
            let command = try state.command(in: session.engine)
            guard session.perform(command, named: name) else { return show(.unusable) }
            if state.kind != .title, let first = state.groups.first?.id { session.selectBoundary(first) }
            clearBoundarySuggestions()
        } catch {
            boundarySuggestions = state.isEmpty ? nil : state
            onSuggestionsChange?()
            show(AIFailure(error))
        }
    }

    func clearBoundarySuggestions() {
        guard boundarySuggestions != nil else { return }
        boundarySuggestions = nil
        onSuggestionsChange?()
        scheduleWaitingAppSuggestion()
    }

    private func clearAllSuggestionsForBoundaries() {
        clearSuggestions()
        clearTagSuggestions()
        clearBoundarySuggestions()
    }

    private func showBoundarySuggestions(_ result: BoundarySuggestionState) {
        var state = result
        state.prune(in: session.engine.state)
        guard !state.isEmpty, state.preview(in: session.engine) != nil else { return show(.nothingSuggested) }
        boundarySuggestions = state
        onSuggestionsChange?()
        AccessibilityNotification.Announcement(String(localized: "\(state.groups.count) AI suggestions")).post()
    }
}

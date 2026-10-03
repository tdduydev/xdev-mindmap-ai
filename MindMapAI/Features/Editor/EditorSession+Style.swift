import Foundation
import MindMapDomain
import MindMapGraph

/// Whether the targets share a value, for menu checkmarks and the inspector.
enum StyleCoverage<Value: Hashable>: Hashable {
    case none
    /// Every target has this value.
    case all(Value)
    case mixed
}

// A topic's colour and symbol (MM-32, docs/node-organization.md *Colour and
// symbol*). Both act on every selected topic, like tags; each pick is one
// `SetNodeStyleCommand`, so one undo step.
extension EditorSession {
    /// The topics a colour applies to: the central topic keeps its navy card
    /// (its colour would not show, and it would recolour every branch).
    func colorTargets(_ ids: [NodeID]? = nil) -> [NodeID] {
        (ids ?? orderedSelection).filter { $0 != rootID && engine.state.node($0) != nil }
    }

    func symbolTargets(_ ids: [NodeID]? = nil) -> [NodeID] {
        (ids ?? orderedSelection).filter { engine.state.node($0) != nil }
    }

    var canColorSelection: Bool { !colorTargets().isEmpty }
    var canSetSelectionSymbol: Bool { !symbolTargets().isEmpty }

    /// A token this build does not know reads as no colour, as on the canvas.
    func colorCoverage(_ ids: [NodeID]? = nil) -> StyleCoverage<TopicColor?> {
        coverage(of: colorTargets(ids)) { $0.color.flatMap { $0.isKnown ? $0 : nil } }
    }

    func symbolCoverage(_ ids: [NodeID]? = nil) -> StyleCoverage<String?> {
        coverage(of: symbolTargets(ids)) { $0.symbol }
    }

    /// Sets or clears the colour of the targets that do not have it yet:
    /// one "Change Color" step.
    func setColor(_ color: TopicColor?, on ids: [NodeID]? = nil) {
        let targets = colorTargets(ids).filter { engine.state.node($0)?.color != color }
        guard !targets.isEmpty else { return }
        perform(SetNodeStyleCommand(nodeIDs: targets, color: .set(color)), named: String(localized: "Change Color"))
    }

    /// Sets a catalogue symbol or an emoji (first character kept), or clears
    /// it with nil or blank text: one "Change Symbol" step.
    func setSymbol(_ text: String?, on ids: [NodeID]? = nil) {
        let symbol = text.flatMap(TopicSymbol.normalized)
        let targets = symbolTargets(ids).filter { engine.state.node($0)?.symbol != symbol }
        guard !targets.isEmpty else { return }
        perform(SetNodeStyleCommand(nodeIDs: targets, symbol: .set(symbol)), named: String(localized: "Change Symbol"))
    }

    /// Opens the symbol picker for the targets.
    func beginChoosingSymbol(for ids: [NodeID]? = nil) {
        let targets = symbolTargets(ids)
        guard !targets.isEmpty else { return }
        symbolPickerTargets = targets
    }

    private func coverage<Value: Hashable>(of ids: [NodeID], _ value: (MindNode) -> Value) -> StyleCoverage<Value> {
        let values = ids.compactMap { engine.state.node($0) }.map(value)
        guard let first = values.first else { return .none }
        return values.allSatisfy { $0 == first } ? .all(first) : .mixed
    }
}

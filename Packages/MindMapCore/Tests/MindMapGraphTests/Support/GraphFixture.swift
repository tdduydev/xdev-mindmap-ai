import Foundation
import MindMapDomain
@testable import MindMapGraph
import Synchronization
import Testing

/// A clock tests can move by hand, so timestamps are predictable.
final class TestClock: Sendable {
    private let current = Mutex(Date(timeIntervalSinceReferenceDate: 800_000_000))

    var now: Date { current.withLock { $0 } }

    func advance(by seconds: TimeInterval = 1) {
        current.withLock { $0 = $0.addingTimeInterval(seconds) }
    }

    /// Each reading is one second after the previous one.
    var ticking: @Sendable () -> Date {
        { [self] in
            current.withLock { date in
                date = date.addingTimeInterval(1)
                return date
            }
        }
    }
}

/// Builds a map from an indented outline, two spaces per level:
///
///     Root
///       A
///         A1
///       B
struct GraphFixture {
    var engine: GraphEngine
    private(set) var ids: [String: NodeID] = [:]

    init(_ outline: String, clock: TestClock = TestClock()) throws {
        engine = try GraphEngine(state: GraphState(map: MindMap(title: "Test map")), clock: clock.ticking)
        var parents: [NodeID] = []
        for line in outline.split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            let depth = line.prefix { $0 == " " }.count / 2
            let title = line.trimmingCharacters(in: .whitespaces)
            parents.removeLast(parents.count - depth)
            let id = NodeID()
            let insertion: NodeInsertion = parents.last.map { .child(of: $0) } ?? .root
            try engine.execute(AddNodeCommand(nodeID: id, insertion, title: title))
            ids[title] = id
            parents.append(id)
        }
    }

    var state: GraphState { engine.state }

    subscript(title: String) -> NodeID {
        guard let id = ids[title] else { preconditionFailure("No node titled \(title) in the fixture") }
        return id
    }

    /// Child titles of a node, in display order.
    func childTitles(of title: String) -> [String] {
        state.children(of: self[title]).map(\.title)
    }

    /// The visible outline rendered back to indented text.
    var outline: String {
        state.visibleOutline()
            .compactMap { item in
                state.node(item.nodeID).map { String(repeating: "  ", count: item.depth) + $0.title }
            }
            .joined(separator: "\n")
    }
}

/// Content equality that ignores the map's "last edited" time, which every
/// step (undo included) moves forward on purpose.
func sameContent(_ lhs: GraphState, _ rhs: GraphState) -> Bool {
    var leftMap = lhs.map
    leftMap.updatedAt = rhs.map.updatedAt
    return leftMap == rhs.map && lhs.nodes == rhs.nodes && lhs.edges == rhs.edges
        && lhs.tags == rhs.tags && lhs.nodeTags == rhs.nodeTags && lhs.groups == rhs.groups
}

/// Runs a command, then checks that undo restores the state before it exactly
/// and redo the state after it. Returns the change set.
@discardableResult
func expectUndoAndRedo(
    _ command: any GraphCommand,
    on fixture: inout GraphFixture,
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> GraphChangeSet {
    let before = fixture.state
    let changes = try fixture.engine.execute(command)
    let after = fixture.state
    #expect(!changes.isEmpty, "the command changed nothing", sourceLocation: sourceLocation)
    fixture.engine.undo()
    #expect(sameContent(fixture.state, before), "undo", sourceLocation: sourceLocation)
    fixture.engine.redo()
    #expect(sameContent(fixture.state, after), "redo", sourceLocation: sourceLocation)
    return changes
}

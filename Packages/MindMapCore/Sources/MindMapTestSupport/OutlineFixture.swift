import Foundation
import MindMapDomain
import MindMapGraph
import Synchronization

/// A map built from an indented outline, two spaces per level, for tests
/// outside the graph module:
///
///     Root
///       A
///         A1
///       B
public struct OutlineFixture {
    public var engine: GraphEngine
    private var ids: [String: NodeID] = [:]

    public init(_ outline: String, mapTitle: String = "Test map") throws {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let clock = TickingClock(start: start)
        engine = try GraphEngine(
            state: GraphState(map: MindMap(title: mapTitle, createdAt: start)),
            clock: { clock.tick() }
        )
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

    public var state: GraphState { engine.state }

    public subscript(title: String) -> NodeID {
        guard let id = ids[title] else { preconditionFailure("No topic titled \(title) in the fixture") }
        return id
    }

    /// Child titles of a topic, in display order.
    public func childTitles(of title: String) -> [String] {
        state.children(of: self[title]).map(\.title)
    }
}

/// Each reading is one second after the previous one, so timestamps and
/// sibling order are predictable.
private final class TickingClock: Sendable {
    private let current: Mutex<Date>

    init(start: Date) {
        current = Mutex(start)
    }

    func tick() -> Date {
        current.withLock { date in
            date = date.addingTimeInterval(1)
            return date
        }
    }
}

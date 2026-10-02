import CoreGraphics
import Foundation
import MindMapDomain
import MindMapGraph
@testable import MindMapLayout

/// Builds a graph straight from node values, without running commands, so a
/// 1,000-topic map is cheap to set up. IDs come from a counter, so building the
/// same outline twice gives the same graph.
///
///     Root
///       A
///         A1
///       B
struct LayoutFixture {
    let map: MindMap
    private(set) var nodes: [MindNode] = []
    private(set) var ids: [String: NodeID] = [:]
    var edges: [MindEdge] = []
    private var childCounts: [NodeID: Int] = [:]

    init(_ outline: String) {
        map = MindMap(id: MapID(Self.uuid(0)), title: "Layout test")
        var parents: [NodeID] = []
        for line in outline.split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            let depth = line.prefix { $0 == " " }.count / 2
            parents.removeLast(parents.count - depth)
            let id = add(line.trimmingCharacters(in: .whitespaces), parent: parents.last)
            parents.append(id)
        }
    }

    /// A random tree of `count` topics, the same tree for the same seed.
    init(randomTreeOf count: Int, seed: UInt64) {
        map = MindMap(id: MapID(Self.uuid(0)), title: "Random")
        var random = SplitMix64(seed: seed)
        var all: [NodeID] = [add("T0", parent: nil)]
        for index in 1..<count {
            // Biased toward recent topics, so the tree has depth as well as width.
            let window = min(all.count, 12)
            let parent = random.nextInt(below: 3) == 0
                ? all[random.nextInt(below: all.count)]
                : all[all.count - 1 - random.nextInt(below: window)]
            all.append(add("T\(index)", parent: parent))
        }
    }

    @discardableResult
    mutating func add(_ title: String, parent: NodeID?, collapsed: Bool = false) -> NodeID {
        let id = NodeID(Self.uuid(nodes.count + 1))
        let siblings = parent.map { childCounts[$0, default: 0] } ?? 0
        if let parent { childCounts[parent] = siblings + 1 }
        nodes.append(MindNode(
            id: id,
            mapID: map.id,
            parentID: parent,
            title: title,
            sortOrder: Double(siblings),
            isCollapsed: collapsed,
            createdAt: Date(timeIntervalSinceReferenceDate: 800_000_000)
        ))
        ids[title] = id
        return id
    }

    mutating func collapse(_ title: String) {
        guard let index = nodes.firstIndex(where: { $0.id == self[title] }) else { return }
        nodes[index].isCollapsed = true
    }

    mutating func link(_ source: String, _ target: String) {
        edges.append(MindEdge(
            id: EdgeID(Self.uuid(10_000 + edges.count)),
            mapID: map.id,
            sourceNodeID: self[source],
            targetNodeID: self[target],
            createdAt: Date(timeIntervalSinceReferenceDate: 800_000_000)
        ))
    }

    var state: GraphState {
        var withRoot = map
        withRoot.rootNodeID = nodes.first?.id
        return GraphState(map: withRoot, nodes: nodes, edges: edges)
    }

    func engine() throws -> GraphEngine {
        try GraphEngine(state: state)
    }

    subscript(title: String) -> NodeID {
        guard let id = ids[title] else { preconditionFailure("No topic titled \(title) in the fixture") }
        return id
    }

    private static func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", value))!
    }
}

/// A tiny seeded generator, so "random" test data is the same on every run.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func nextInt(below bound: Int) -> Int {
        Int(next() % UInt64(bound))
    }
}

extension MapLayout {
    func frame(_ id: NodeID) -> CGRect {
        guard let node = nodes[id] else { preconditionFailure("Topic is not laid out") }
        return node.frame
    }

    /// Pairs of topics whose frames overlap by more than rounding noise.
    var overlappingPairs: [(NodeID, NodeID)] {
        let entries = nodes.map { ($0.key, $0.value.frame) }
        var result: [(NodeID, NodeID)] = []
        for i in entries.indices {
            for j in entries.indices where j > i {
                let overlap = entries[i].1.intersection(entries[j].1)
                if !overlap.isNull, overlap.width > 0.001, overlap.height > 0.001 {
                    result.append((entries[i].0, entries[j].0))
                }
            }
        }
        return result
    }
}

/// Sizes that vary like real titles: some long and wrapped onto several lines.
func variedSizes(for state: GraphState, seed: UInt64) -> [NodeID: CGSize] {
    var random = SplitMix64(seed: seed)
    var sizes: [NodeID: CGSize] = [:]
    for id in state.nodes.keys.sorted() {
        let width = CGFloat(60 + random.nextInt(below: 200))
        let lines = CGFloat(1 + random.nextInt(below: 4))
        sizes[id] = CGSize(width: width, height: 20 * lines + 12)
    }
    return sizes
}

import Foundation
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import Testing

@Suite("Persistence benchmarks")
struct PersistenceBenchmarks {
    /// Opt in with MM2_BENCHMARK=1. Creation is excluded from load timing.
    @Test func loadAndSaveAtOneAndTenThousandTopics() async throws {
        guard ProcessInfo.processInfo.environment["MM2_BENCHMARK"] == "1" else { return }
        for count in [1_000, 10_000] {
            let folder = FileManager.default.temporaryDirectory.appending(path: "benchmark-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let url = folder.appending(path: "map.store")
            let repository = try PersistenceController.makeRepository(at: .file(url))
            let graph = makeGraph(topicCount: count)
            try await repository.create(graph)

            let loadStart = ContinuousClock.now
            let loaded = try #require(try await repository.loadGraph(for: graph.map.id))
            let loadTime = loadStart.duration(to: .now)
            #expect(loaded.nodes.count == count)

            var engine = try GraphEngine(state: loaded)
            let root = try #require(loaded.map.rootNodeID)
            let changes = try engine.execute(AddNodeCommand(.child(of: root), title: "New topic"))
            let saveStart = ContinuousClock.now
            try await repository.save(changes, map: engine.state.map)
            let saveTime = saveStart.duration(to: .now)
            print("MM2_BENCHMARK topics=\(count) load=\(loadTime) save=\(saveTime)")
        }
    }

    private func makeGraph(topicCount: Int) -> GraphState {
        let mapID = MapID()
        let rootID = NodeID()
        let map = MindMap(id: mapID, title: "Benchmark", rootNodeID: rootID)
        var nodes = [MindNode(id: rootID, mapID: mapID, parentID: nil, title: "Benchmark")]
        nodes.reserveCapacity(topicCount)
        for index in 1..<topicCount {
            nodes.append(MindNode(mapID: mapID, parentID: rootID, title: "Topic \(index)", sortOrder: Double(index)))
        }
        return GraphState(map: map, nodes: nodes, edges: [])
    }
}

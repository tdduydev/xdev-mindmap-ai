import Foundation
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import Testing

/// Times for opening and saving 1,000- and 10,000-topic maps in an on-disk
/// store. They are printed, never asserted: they depend on the machine and
/// what else it is doing, and a gate that fails at random gets ignored.
/// Off by default, as the 10,000-topic run adds seconds to every test run:
///
///     MINDMAP_BENCHMARKS=1 swift test --package-path Packages/MindMapCore --filter PersistenceBenchmarks
///
/// Add `-c release -Xswiftc -enable-testing` for the numbers a shipped build
/// sees. The last recorded results are in docs/data-model.md.
@Suite(
    "Persistence benchmarks",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["MINDMAP_BENCHMARKS"] == "1")
)
struct PersistenceBenchmarks {
    static let opens = 3
    static let savesPerKind = 10

    @Test(arguments: [1_000, 10_000])
    func openAndSave(topicCount: Int) async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "benchmark-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "map.store")
        let graph = Self.map(topicCount: topicCount)

        // The app has fetched the library before any map opens, so SwiftData
        // is warm; without this the first case would also time that set-up.
        try await Self.warmUp(in: folder)

        let writer = try PersistenceController.makeRepository(at: .file(url))
        let create = try await Self.time { try await writer.create(graph) }

        var loads: [Duration] = []
        var prepares: [Duration] = []
        var opened: (SwiftDataMapRepository, GraphEngine)?
        for _ in 0..<Self.opens {
            // A new container each time: nothing cached, as after a relaunch.
            let repository = try PersistenceController.makeRepository(at: .file(url))
            let (stored, load) = try await Self.time { try await repository.loadGraph(for: graph.map.id) }
            let loaded = try #require(stored)
            #expect(loaded == graph)
            // What EditorSession.open does after loading, before anything is drawn.
            let (engine, prepare) = try await Self.time {
                try GraphEngine(state: try GraphRepair.repair(loaded, now: .now).state)
            }
            loads.append(load)
            prepares.append(prepare)
            opened = (repository, engine)
        }
        // Saves go through the repository that loaded the map, as in the editor.
        let (repository, openedEngine) = try #require(opened)
        var engine = openedEngine

        let root = try #require(graph.map.rootNodeID)
        var adds: [Duration] = []
        var renames: [Duration] = []
        for index in 0..<Self.savesPerKind {
            let added = NodeID()
            let add = try engine.execute(AddNodeCommand(nodeID: added, .child(of: root), title: "New \(index)"))
            adds.append(try await Self.time { try await repository.save(add, map: engine.state.map) })
            let rename = try engine.execute(UpdateNodeCommand(nodeID: added, changes: [.title("Renamed \(index)")]))
            renames.append(try await Self.time { try await repository.save(rename, map: engine.state.map) })
        }
        #expect(try await repository.loadGraph(for: graph.map.id) == engine.state)

        print(
            "PersistenceBenchmark topics=\(topicCount)",
            "create=\(Self.ms(create))",
            "loadGraph(first/median/max)=\(Self.summary(loads))",
            "repairAndEngine(first/median/max)=\(Self.summary(prepares))",
            "openMap(median)=\(Self.ms(Self.median(loads) + Self.median(prepares)))",
            "saveAdd(first/median/max)=\(Self.summary(adds))",
            "saveRename(first/median/max)=\(Self.summary(renames))"
        )
    }

    /// A tree six wide at every level, a note on every tenth topic and a
    /// cross-link per hundred, closer to a real map than one flat level.
    static func map(topicCount: Int) -> GraphState {
        let mapID = MapID()
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let ids = (0..<topicCount).map { _ in NodeID() }
        let branching = 6
        let nodes = ids.indices.map { index in
            MindNode(
                id: ids[index],
                mapID: mapID,
                parentID: index == 0 ? nil : ids[(index - 1) / branching],
                title: index == 0 ? "Benchmark" : "Topic \(index)",
                note: index.isMultiple(of: 10) ? "Note for topic \(index)" : nil,
                sortOrder: index == 0 ? 0 : Double((index - 1) % branching),
                createdAt: now
            )
        }
        let edges = stride(from: 1, to: topicCount - 7, by: 100).map { index in
            MindEdge(mapID: mapID, sourceNodeID: ids[index], targetNodeID: ids[index + 7], createdAt: now)
        }
        let map = MindMap(id: mapID, title: "Benchmark", rootNodeID: ids[0], createdAt: now)
        return GraphState(map: map, nodes: nodes, edges: edges)
    }

    static func time<T>(_ work: () async throws -> T) async rethrows -> (T, Duration) {
        let start = ContinuousClock.now
        let result = try await work()
        return (result, start.duration(to: .now))
    }

    static func time(_ work: () async throws -> Void) async rethrows -> Duration {
        let start = ContinuousClock.now
        try await work()
        return start.duration(to: .now)
    }

    static func ms(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        let milliseconds = Double(seconds) * 1_000 + Double(attoseconds) / 1e15
        return String(format: "%.1fms", milliseconds)
    }

    static func median(_ durations: [Duration]) -> Duration {
        durations.sorted()[durations.count / 2]
    }

    static func summary(_ durations: [Duration]) -> String {
        [durations[0], median(durations), durations.max()!].map(ms).joined(separator: "/")
    }

    private static func warmUp(in folder: URL) async throws {
        let repository = try PersistenceController.makeRepository(at: .file(folder.appending(path: "warm-up.store")))
        let graph = map(topicCount: 10)
        try await repository.create(graph)
        _ = try await repository.loadGraph(for: graph.map.id)
    }
}

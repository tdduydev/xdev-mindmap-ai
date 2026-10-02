import Foundation
import MindMapDomain
import MindMapGraph
@testable import MindMapPersistence
import SwiftData
import Testing

@Suite("Stored theme")
struct ThemePersistenceTests {
    let container: ModelContainer
    let repository: SwiftDataMapRepository

    init() throws {
        container = try PersistenceController.makeContainer(at: .inMemory)
        repository = SwiftDataMapRepository(modelContainer: container)
    }

    @Test func changedThemeReloads() async throws {
        var engine = try GraphEngine(state: GraphState.newMap(title: "Plan"))
        try await repository.create(engine.state)

        let changes = try engine.execute(ChangeThemeCommand(theme: .xdevBlue))
        try await repository.save(changes, map: engine.state.map)

        let loaded = try #require(try await repository.loadGraph(for: engine.state.map.id))
        #expect(loaded.map.theme == .xdevBlue)
    }

    /// A newer version on another device may store a theme this build lacks (FR-THM-03).
    @Test func unknownStoredThemeLoadsAsStandard() async throws {
        let graph = GraphState.newMap(title: "Future")
        try await repository.create(graph)
        let context = ModelContext(container)
        let mapID = graph.map.id.rawValue
        let record = try #require(try context.fetch(FetchDescriptor<MapRecord>(predicate: #Predicate { $0.mapID == mapID })).first)
        record.themeRaw = "aurora"
        try context.save()

        let loaded = try #require(try await repository.loadGraph(for: graph.map.id))
        #expect(loaded.map.theme == .standard)
    }
}

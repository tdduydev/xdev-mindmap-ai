import Foundation
import MindMapDomain
import MindMapGraph
import MindMapSearch
import Testing

@Suite("Find in map")
struct MapFindTests {
    @Test func findsTitlesAndNotesInReadingOrderIncludingCollapsedBranches() throws {
        var engine = try GraphEngine(state: GraphState.newMap(title: "Kế hoạch"))
        let rootID = try #require(engine.state.map.rootNodeID)
        let a = NodeID()
        let a1 = NodeID()
        let b = NodeID()
        let c = NodeID()
        try engine.execute(BatchCommand([
            AddNodeCommand(nodeID: a, .child(of: rootID), title: "Thiết kế"),
            AddNodeCommand(nodeID: a1, .child(of: a), title: "Đặc tả", note: "thiết kế chi tiết"),
            AddNodeCommand(nodeID: b, .child(of: rootID), title: "Triển khai"),
            AddNodeCommand(nodeID: c, .child(of: rootID), title: "THIET KE lại"),
            UpdateNodeCommand(nodeID: a, .isCollapsed(true)),
        ]))

        #expect(MapFind.matches(SearchQuery("thiet ke"), in: engine.state) == [a, a1, c])
        #expect(MapFind.matches(SearchQuery("dac ta"), in: engine.state) == [a1])
        #expect(MapFind.matches(SearchQuery("ke hoach"), in: engine.state) == [rootID])
        #expect(MapFind.matches(SearchQuery("nothing"), in: engine.state).isEmpty)
        #expect(MapFind.matches(SearchQuery(""), in: engine.state).isEmpty)
    }

    @Test func emptyMapHasNoMatches() throws {
        let state = GraphState(map: MindMap(title: "Empty"))

        #expect(MapFind.matches(SearchQuery("empty"), in: state).isEmpty)
    }
}

@Suite("Find by tag")
struct MapFindTagTests {
    @Test func tagNamesMatchWithSearchFoldingAndHashWordsMatchOnlyTags() throws {
        var engine = try GraphEngine(state: GraphState.newMap(title: "Plan"))
        let rootID = try #require(engine.state.map.rootNodeID)
        let a = NodeID()
        let b = NodeID()
        let c = NodeID()
        try engine.execute(BatchCommand([
            AddNodeCommand(nodeID: a, .child(of: rootID), title: "Budget"),
            AddNodeCommand(nodeID: b, .child(of: rootID), title: "Việc nhà"),
            AddNodeCommand(nodeID: c, .child(of: rootID), title: "Hotels"),
            TagNodesCommand(nodeIDs: [a], add: [.named("Việc cần làm")]),
            TagNodesCommand(nodeIDs: [c], add: [.named("Việc cần làm"), .named("Gấp")]),
        ]))

        #expect(MapFind.matches(SearchQuery("viec"), in: engine.state) == [a, b, c], "titles and tag names")
        #expect(MapFind.matches(SearchQuery("#viec"), in: engine.state) == [a, c], "a # word matches tags only")
        #expect(MapFind.matches(SearchQuery("#viec #gap"), in: engine.state) == [c])
        #expect(MapFind.matches(SearchQuery("#viec hotel"), in: engine.state) == [c])
        #expect(MapFind.matches(SearchQuery("#"), in: engine.state).isEmpty)
    }
}

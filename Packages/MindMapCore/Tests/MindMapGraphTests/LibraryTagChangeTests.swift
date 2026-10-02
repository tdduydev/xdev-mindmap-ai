import Foundation
import MindMapDomain
@testable import MindMapGraph
import Testing

@Suite("Library tag changes")
struct LibraryTagChangeTests {
    static let outline = """
    Root
      A
      B
    """

    @Test func renamingASharedTagKeepsTheMapsHistory() throws {
        var fixture = try GraphFixture(Self.outline)
        let sharedID = try TagCommandTests.addSharedTag("Việc", to: &fixture)
        try fixture.engine.execute(TagNodesCommand(nodeIDs: [fixture["A"]], add: [.existing(sharedID)]))
        var renamed = try #require(fixture.state.tag(sharedID))
        renamed.name = "Công việc"

        let result = fixture.engine.apply(LibraryTagChange(savedTags: [renamed]))

        #expect(!result.clearedHistory)
        #expect(fixture.engine.canUndo)
        #expect(fixture.state.tags(of: fixture["A"]).map(\.name) == ["Công việc"])
        #expect(result.changes.tags[sharedID]?.after?.name == "Công việc")
    }

    @Test func deletingLinksClearsHistorySoUndoCannotReplayThem() throws {
        var fixture = try GraphFixture(Self.outline)
        let sharedID = try TagCommandTests.addSharedTag("Việc", to: &fixture)
        try fixture.engine.execute(TagNodesCommand(nodeIDs: [fixture["A"]], add: [.existing(sharedID)]))
        let link = try #require(fixture.state.nodeTags(of: fixture["A"]).first)

        let result = fixture.engine.apply(LibraryTagChange(deletedTagIDs: [sharedID], deletedNodeTagIDs: [link.id]))

        #expect(result.clearedHistory)
        #expect(!fixture.engine.canUndo)
        #expect(fixture.state.tag(sharedID) == nil)
        #expect(fixture.state.nodeTags.isEmpty)
        #expect(result.changes.nodeTags[link.id]?.after == nil)
    }

    @Test func aMapTagMadeSharedStaysAndClearsHistory() throws {
        var fixture = try GraphFixture(Self.outline)
        let id = TagID()
        try fixture.engine.execute(TagNodesCommand(nodeIDs: [fixture["A"]], add: [.named("Việc", newTagID: id)]))
        var shared = try #require(fixture.state.tag(id))
        shared.mapID = nil

        let result = fixture.engine.apply(LibraryTagChange(savedTags: [shared]))

        #expect(result.clearedHistory, "undoing the tag's creation would delete a library tag")
        #expect(fixture.state.tag(id)?.isShared == true)
        #expect(fixture.state.mapTags.isEmpty)
        #expect(fixture.state.sharedTags.map(\.id) == [id])
    }

    @Test func aTagThatBecameAnotherMapsLeavesThisMap() throws {
        var fixture = try GraphFixture(Self.outline)
        let sharedID = try TagCommandTests.addSharedTag("Việc", to: &fixture)
        var moved = try #require(fixture.state.tag(sharedID))
        moved.mapID = MapID()

        fixture.engine.apply(LibraryTagChange(savedTags: [moved]))

        #expect(fixture.state.tag(sharedID) == nil)
    }

    @Test func linksOfOtherMapsAreIgnoredAndApplyingTwiceChangesNothing() throws {
        var fixture = try GraphFixture(Self.outline)
        let sharedID = try TagCommandTests.addSharedTag("Việc", to: &fixture)
        let own = MindNodeTag(mapID: fixture.state.map.id, nodeID: fixture["B"], tagID: sharedID)
        let foreign = MindNodeTag(mapID: MapID(), nodeID: NodeID(), tagID: sharedID)
        let change = LibraryTagChange(savedNodeTags: [own, foreign])

        fixture.engine.apply(change)
        let again = fixture.engine.apply(change)

        #expect(fixture.state.nodeTags.values.map(\.id) == [own.id])
        #expect(again.changes.isEmpty)
        #expect(!again.clearedHistory)
    }

    @Test func tagListsAndCounts() throws {
        var fixture = try GraphFixture(Self.outline)
        let sharedID = try TagCommandTests.addSharedTag("Zeta", to: &fixture)
        let first = TagID()
        let second = TagID()
        try fixture.engine.execute(BatchCommand([
            CreateTagCommand(tagID: first, name: "Beta"),
            CreateTagCommand(tagID: second, name: "Alpha"),
            TagNodesCommand(nodeIDs: [fixture["A"], fixture["B"]], add: [.existing(first), .existing(sharedID)]),
        ]))

        #expect(fixture.state.mapTags.map(\.id) == [first, second], "map tags keep their list order")
        #expect(fixture.state.sharedTags.map(\.id) == [sharedID])
        #expect(fixture.state.tagUseCounts() == [first: 2, sharedID: 2])
        #expect(fixture.state.nodeIDs(taggedWith: first) == [fixture["A"], fixture["B"]])
    }
}

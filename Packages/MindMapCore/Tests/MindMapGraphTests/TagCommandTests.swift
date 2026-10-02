import Foundation
import MindMapDomain
@testable import MindMapGraph
import Testing

@Suite("Tags")
struct TagCommandTests {
    static let outline = """
    Root
      A
      B
    """

    /// A shared tag as the library stores it: no map.
    static func addSharedTag(_ name: String, to fixture: inout GraphFixture) throws -> TagID {
        let tag = MindTag(mapID: nil, name: name, createdAt: Date(timeIntervalSinceReferenceDate: 1))
        try fixture.engine.execute(InsertTagForTest(tag: tag))
        return tag.id
    }

    @Test func createMakesAMapTagWithACleanName() throws {
        var fixture = try GraphFixture(Self.outline)
        let id = TagID()

        try expectUndoAndRedo(CreateTagCommand(tagID: id, name: "  #Kế  hoạch ", color: .green), on: &fixture)

        let tag = try #require(fixture.state.tag(id))
        #expect(tag.name == "Kế hoạch")
        #expect(tag.mapID == fixture.state.map.id)
        #expect(tag.color == .green)
    }

    @Test func createWithAnExistingKeyUsesTheExistingTag() throws {
        var fixture = try GraphFixture(Self.outline)
        try fixture.engine.execute(CreateTagCommand(name: "Việc"))

        let changes = try fixture.engine.execute(CreateTagCommand(name: "VIỆC"))

        #expect(changes.isEmpty)
        #expect(fixture.state.tags.count == 1)
    }

    @Test func blankOrLongNamesAreRefused() throws {
        var fixture = try GraphFixture(Self.outline)

        #expect(throws: GraphError.invalidTagName) { try fixture.engine.execute(CreateTagCommand(name: " # ")) }
        #expect(throws: GraphError.invalidTagName) {
            try fixture.engine.execute(CreateTagCommand(name: String(repeating: "a", count: 41)))
        }
    }

    @Test func tagNodesByNameCreatesTheTagAndLinksInOneStep() throws {
        var fixture = try GraphFixture(Self.outline)
        let newID = TagID()

        let changes = try expectUndoAndRedo(
            TagNodesCommand(nodeIDs: [fixture["A"], fixture["B"]], add: [.named("Việc", newTagID: newID)], origin: .ai),
            on: &fixture
        )

        #expect(changes.tags.count == 1)
        #expect(changes.nodeTags.count == 2)
        #expect(fixture.state.tags(of: fixture["A"]).map(\.id) == [newID])
        #expect(fixture.state.nodeTags(of: fixture["B"]).first?.origin == .ai)
    }

    @Test func taggingReusesTagsByKeyAndPrefersSharedOnes() throws {
        var fixture = try GraphFixture(Self.outline)
        try fixture.engine.execute(CreateTagCommand(name: "việc"))
        let shared = try Self.addSharedTag("Việc", to: &fixture)

        try fixture.engine.execute(TagNodesCommand(nodeIDs: [fixture["A"]], add: [.named("VIỆC")]))

        #expect(fixture.state.tags(of: fixture["A"]).map(\.id) == [shared])
        #expect(fixture.state.tags.count == 2)
    }

    @Test func taggingTwiceKeepsOneLink() throws {
        var fixture = try GraphFixture(Self.outline)
        let id = TagID()
        try fixture.engine.execute(CreateTagCommand(tagID: id, name: "Việc"))
        try fixture.engine.execute(TagNodesCommand(nodeIDs: [fixture["A"]], add: [.existing(id)]))

        let changes = try fixture.engine.execute(TagNodesCommand(nodeIDs: [fixture["A"]], add: [.existing(id), .named("việc")]))

        #expect(changes.isEmpty)
        #expect(fixture.state.nodeTags.count == 1)
    }

    @Test func untagRemovesOnlyThatTagFromThoseTopics() throws {
        var fixture = try GraphFixture(Self.outline)
        let work = TagID()
        let home = TagID()
        try fixture.engine.execute(TagNodesCommand(
            nodeIDs: [fixture["A"], fixture["B"]],
            add: [.named("Work", newTagID: work), .named("Home", newTagID: home)]
        ))

        try expectUndoAndRedo(TagNodesCommand(nodeIDs: [fixture["A"]], remove: [work]), on: &fixture)

        #expect(fixture.state.tags(of: fixture["A"]).map(\.id) == [home])
        #expect(Set(fixture.state.tags(of: fixture["B"]).map(\.id)) == [work, home])
        #expect(fixture.state.tag(work) != nil)
    }

    @Test func taggingRefusesMissingTopicsAndTags() throws {
        var fixture = try GraphFixture(Self.outline)
        let ghostNode = NodeID()
        let ghostTag = TagID()

        #expect(throws: GraphError.nodeNotFound(ghostNode)) {
            try fixture.engine.execute(TagNodesCommand(nodeIDs: [ghostNode], add: [.named("Việc")]))
        }
        #expect(throws: GraphError.tagNotFound(ghostTag)) {
            try fixture.engine.execute(TagNodesCommand(nodeIDs: [fixture["A"]], add: [.existing(ghostTag)]))
        }
        #expect(fixture.state.tags.isEmpty)
    }

    @Test func updateRenamesRecoloursAndReorders() throws {
        var fixture = try GraphFixture(Self.outline)
        let id = TagID()
        try fixture.engine.execute(CreateTagCommand(tagID: id, name: "Work"))

        try expectUndoAndRedo(
            UpdateTagCommand(tagID: id, name: .set(" Công  việc "), color: .set(.violet), symbol: .set("briefcase"), sortOrder: .set(5)),
            on: &fixture
        )

        let tag = try #require(fixture.state.tag(id))
        #expect(tag.name == "Công việc")
        #expect(tag.color == .violet)
        #expect(tag.symbol == "briefcase")
        #expect(tag.sortOrder == 5)
    }

    @Test func renamingOntoAnotherTagsNameIsRefused() throws {
        var fixture = try GraphFixture(Self.outline)
        let work = TagID()
        let home = TagID()
        try fixture.engine.execute(CreateTagCommand(tagID: work, name: "Work"))
        try fixture.engine.execute(CreateTagCommand(tagID: home, name: "Home"))

        #expect(throws: GraphError.tagNameTaken(home)) {
            try fixture.engine.execute(UpdateTagCommand(tagID: work, name: .set("HOME")))
        }
        // Changing only the case of its own name is fine.
        try fixture.engine.execute(UpdateTagCommand(tagID: work, name: .set("WORK")))
        #expect(fixture.state.tag(work)?.name == "WORK")
    }

    @Test func sharedTagsAreNotEditedThroughAMap() throws {
        var fixture = try GraphFixture(Self.outline)
        let shared = try Self.addSharedTag("Việc", to: &fixture)

        #expect(throws: GraphError.sharedTagIsLibraryData(shared)) {
            try fixture.engine.execute(UpdateTagCommand(tagID: shared, name: .set("Other")))
        }
        #expect(throws: GraphError.sharedTagIsLibraryData(shared)) {
            try fixture.engine.execute(DeleteTagCommand(tagID: shared))
        }
        // Putting it on a topic is a map edit.
        try fixture.engine.execute(TagNodesCommand(nodeIDs: [fixture["A"]], add: [.existing(shared)]))
        #expect(fixture.state.tags(of: fixture["A"]).map(\.id) == [shared])
    }

    @Test func deleteRemovesTheTagAndEveryLink() throws {
        var fixture = try GraphFixture(Self.outline)
        let id = TagID()
        try fixture.engine.execute(TagNodesCommand(nodeIDs: [fixture["A"], fixture["B"]], add: [.named("Việc", newTagID: id)]))

        let changes = try expectUndoAndRedo(DeleteTagCommand(tagID: id), on: &fixture)

        #expect(changes.deletedTagIDs == [id])
        #expect(changes.deletedNodeTagIDs.count == 2)
        #expect(fixture.state.nodeTags.isEmpty)
        #expect(fixture.state.node(fixture["A"]) != nil)
    }

    @Test func mergeMovesLinksAndDropsDuplicates() throws {
        var fixture = try GraphFixture(Self.outline)
        let work = TagID()
        let job = TagID()
        try fixture.engine.execute(TagNodesCommand(nodeIDs: [fixture["A"]], add: [.named("Work", newTagID: work)]))
        try fixture.engine.execute(TagNodesCommand(nodeIDs: [fixture["A"], fixture["B"]], add: [.named("Job", newTagID: job)]))

        try expectUndoAndRedo(MergeTagsCommand(into: work, merging: [job]), on: &fixture)

        #expect(fixture.state.tag(job) == nil)
        #expect(fixture.state.tags(of: fixture["A"]).map(\.id) == [work])
        #expect(fixture.state.tags(of: fixture["B"]).map(\.id) == [work])
        #expect(fixture.state.nodeTags.count == 2)
    }

    @Test func deletingATopicDeletesItsLinksAndUndoBringsThemBack() throws {
        var fixture = try GraphFixture(Self.outline)
        try fixture.engine.execute(TagNodesCommand(nodeIDs: [fixture["A"]], add: [.named("Việc")]))

        try expectUndoAndRedo(DeleteNodeCommand(nodeID: fixture["A"]), on: &fixture)

        #expect(fixture.state.nodeTags.isEmpty)
        #expect(fixture.state.tags.count == 1)
    }

    @Test func mergingTopicsMovesTheirTagsToTheSurvivor() throws {
        var fixture = try GraphFixture(Self.outline)
        try fixture.engine.execute(TagNodesCommand(nodeIDs: [fixture["A"]], add: [.named("Work")]))
        try fixture.engine.execute(TagNodesCommand(nodeIDs: [fixture["B"]], add: [.named("Work"), .named("Home")]))

        try expectUndoAndRedo(MergeNodesCommand(into: fixture["A"], merging: [fixture["B"]]), on: &fixture)

        #expect(Set(fixture.state.tags(of: fixture["A"]).map(\.name)) == ["Work", "Home"])
        #expect(fixture.state.nodeTags.count == 2)
    }

    /// A link whose tag has not synced yet is kept but not shown.
    @Test func linksWaitingForTheirTagAreHidden() throws {
        let fixture = try GraphFixture(Self.outline)
        let link = MindNodeTag(mapID: fixture.state.map.id, nodeID: fixture["A"], tagID: TagID())
        let state = GraphState(
            map: fixture.state.map, nodes: fixture.state.nodes.values, edges: [], nodeTags: [link]
        )

        #expect(state.nodeTags.count == 1)
        #expect(state.tags(of: fixture["A"]).isEmpty)
        #expect(GraphValidator.validate(state).isEmpty)
    }
}

/// Shared tags are library data; tests put one into a map's state this way.
struct InsertTagForTest: GraphCommand {
    let tag: MindTag

    func execute(in transaction: inout GraphTransaction) throws {
        try transaction.insertTag(tag)
    }
}

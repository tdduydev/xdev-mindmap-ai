import Foundation
import MindMapDomain
@testable import MindMapGraph
import Testing

@Suite("Boundaries")
struct GroupCommandTests {
    static let outline = """
    Root
      A
        A1
      B
      C
      D
      E
    """

    /// The titles a boundary frames, or nil when it is gone.
    static func members(_ id: GroupID, in fixture: GraphFixture) -> [String]? {
        guard let group = fixture.state.group(id) else { return nil }
        return fixture.state.members(of: group)?.compactMap { fixture.state.node($0)?.title }
    }

    static func boundary(from first: String, to last: String, in fixture: inout GraphFixture) throws -> GroupID {
        let id = GroupID()
        try fixture.engine.execute(AddGroupCommand(groupID: id, from: fixture[first], to: fixture[last]))
        return id
    }

    // MARK: Commands

    @Test func addFramesARunInEitherOrder() throws {
        var fixture = try GraphFixture(Self.outline)
        let id = GroupID()

        try expectUndoAndRedo(
            AddGroupCommand(groupID: id, from: fixture["D"], to: fixture["B"], title: "  Phase 1 ", color: .graphite),
            on: &fixture
        )

        let group = try #require(fixture.state.group(id))
        #expect(Self.members(id, in: fixture) == ["B", "C", "D"])
        #expect(group.firstNodeID == fixture["B"])
        #expect(group.parentNodeID == fixture["Root"])
        #expect(group.title == "Phase 1")
        #expect(group.kind == .boundary)
    }

    @Test func aBoundaryAroundOneBranch() throws {
        var fixture = try GraphFixture(Self.outline)
        let id = GroupID()

        try expectUndoAndRedo(AddGroupCommand(groupID: id, from: fixture["A1"]), on: &fixture)

        #expect(Self.members(id, in: fixture) == ["A1"])
    }

    @Test func refusesTheRootAndEndsUnderDifferentParents() throws {
        var fixture = try GraphFixture(Self.outline)

        #expect(throws: GraphError.cannotGroupRoot) {
            try fixture.engine.execute(AddGroupCommand(from: fixture["Root"]))
        }
        #expect(throws: GraphError.notSiblings(fixture["B"])) {
            try fixture.engine.execute(AddGroupCommand(from: fixture["A1"], to: fixture["B"]))
        }
        #expect(fixture.state.groups.isEmpty)
    }

    @Test func refusesTheSameRunTwiceAndCrossingRuns() throws {
        var fixture = try GraphFixture(Self.outline)
        let existing = try Self.boundary(from: "A", to: "C", in: &fixture)

        #expect(throws: GraphError.groupAlreadyCoversRun(existing)) {
            try fixture.engine.execute(AddGroupCommand(from: fixture["C"], to: fixture["A"]))
        }
        #expect(throws: GraphError.groupsWouldCross(existing)) {
            try fixture.engine.execute(AddGroupCommand(from: fixture["B"], to: fixture["D"]))
        }
        // Nesting either way is fine.
        try fixture.engine.execute(AddGroupCommand(from: fixture["B"], to: fixture["C"]))
        try fixture.engine.execute(AddGroupCommand(from: fixture["A"], to: fixture["E"]))
        #expect(fixture.state.groups.count == 3)
    }

    @Test func updateRenamesAndRecolours() throws {
        var fixture = try GraphFixture(Self.outline)
        let id = try Self.boundary(from: "B", to: "C", in: &fixture)

        try expectUndoAndRedo(UpdateGroupCommand(groupID: id, title: .set("Ideas"), color: .set(.teal)), on: &fixture)
        #expect(fixture.state.group(id)?.title == "Ideas")
        #expect(fixture.state.group(id)?.color == .teal)

        try expectUndoAndRedo(UpdateGroupCommand(groupID: id, title: .set("   ")), on: &fixture)
        #expect(fixture.state.group(id)?.title == nil)
        #expect(fixture.state.group(id)?.color == .teal)
    }

    @Test func removeKeepsTheTopics() throws {
        var fixture = try GraphFixture(Self.outline)
        let id = try Self.boundary(from: "B", to: "C", in: &fixture)
        let nodes = fixture.state.nodes

        try expectUndoAndRedo(RemoveGroupCommand(groupID: id), on: &fixture)

        #expect(fixture.state.groups.isEmpty)
        #expect(fixture.state.nodes == nodes)
    }

    @Test func missingBoundaryIsRefused() throws {
        var fixture = try GraphFixture(Self.outline)
        let ghost = GroupID()

        #expect(throws: GraphError.groupNotFound(ghost)) { try fixture.engine.execute(RemoveGroupCommand(groupID: ghost)) }
        #expect(throws: GraphError.groupNotFound(ghost)) {
            try fixture.engine.execute(UpdateGroupCommand(groupID: ghost, title: .set("X")))
        }
    }

    // MARK: Kept valid while topics move

    @Test func aTopicAddedInsideTheRunJoinsIt() throws {
        var fixture = try GraphFixture(Self.outline)
        let id = try Self.boundary(from: "B", to: "D", in: &fixture)

        try fixture.engine.execute(AddNodeCommand(.sibling(after: fixture["B"]), title: "New"))

        #expect(Self.members(id, in: fixture) == ["B", "New", "C", "D"])
    }

    @Test func deletingAnEndMovesItInward() throws {
        var fixture = try GraphFixture(Self.outline)
        let id = try Self.boundary(from: "B", to: "D", in: &fixture)

        try expectUndoAndRedo(DeleteNodeCommand(nodeIDs: [fixture["B"], fixture["D"]]), on: &fixture)

        #expect(Self.members(id, in: fixture) == ["C"])
    }

    @Test func deletingEveryMemberDeletesTheBoundary() throws {
        var fixture = try GraphFixture(Self.outline)
        let id = try Self.boundary(from: "B", to: "C", in: &fixture)

        let changes = try expectUndoAndRedo(DeleteNodeCommand(nodeIDs: [fixture["C"], fixture["B"]]), on: &fixture)

        #expect(changes.deletedGroupIDs == [id])
        #expect(fixture.state.group(id) == nil)
    }

    @Test func deletingTheParentDeletesTheBoundariesUnderIt() throws {
        var fixture = try GraphFixture(Self.outline)
        let id = try Self.boundary(from: "A1", to: "A1", in: &fixture)

        try expectUndoAndRedo(DeleteNodeCommand(nodeID: fixture["A"]), on: &fixture)

        #expect(fixture.state.group(id) == nil)
    }

    @Test func movingAnEndToAnotherParentMovesItInward() throws {
        var fixture = try GraphFixture(Self.outline)
        let id = try Self.boundary(from: "B", to: "D", in: &fixture)

        try expectUndoAndRedo(ReparentNodeCommand(nodeID: fixture["D"], newParentID: fixture["A"]), on: &fixture)

        #expect(Self.members(id, in: fixture) == ["B", "C"])
    }

    @Test func movingAMemberOutOfTheRunLeavesIt() throws {
        var fixture = try GraphFixture(Self.outline)
        let id = try Self.boundary(from: "B", to: "D", in: &fixture)

        try fixture.engine.execute(ReparentNodeCommand(nodeID: fixture["C"], newParentID: fixture["Root"], placement: .last))

        #expect(Self.members(id, in: fixture) == ["B", "D"])
    }

    @Test func anEndReorderedPastTheOtherSwapsTheEnds() throws {
        var fixture = try GraphFixture(Self.outline)
        let id = try Self.boundary(from: "B", to: "C", in: &fixture)

        try expectUndoAndRedo(
            ReparentNodeCommand(nodeID: fixture["B"], newParentID: fixture["Root"], placement: .after(fixture["D"])),
            on: &fixture
        )

        #expect(Self.members(id, in: fixture) == ["C", "D", "B"])
        #expect(GraphValidator.validate(fixture.state).isEmpty)
    }

    @Test func anEndReorderedWithinItsRunKeepsTheMembers() throws {
        var fixture = try GraphFixture(Self.outline)
        let id = try Self.boundary(from: "B", to: "D", in: &fixture)

        try expectUndoAndRedo(
            ReparentNodeCommand(nodeID: fixture["B"], newParentID: fixture["Root"], placement: .after(fixture["C"])),
            on: &fixture
        )

        #expect(Self.members(id, in: fixture) == ["C", "B", "D"])
    }

    @Test func promoteAndDemoteKeepBoundariesValid() throws {
        var fixture = try GraphFixture(Self.outline)
        let id = try Self.boundary(from: "B", to: "C", in: &fixture)

        try expectUndoAndRedo(DemoteNodeCommand(nodeID: fixture["B"]), on: &fixture)
        #expect(Self.members(id, in: fixture) == ["C"])

        try expectUndoAndRedo(PromoteNodeCommand(nodeID: fixture["A1"]), on: &fixture)
        #expect(GraphValidator.validate(fixture.state).isEmpty)
    }

    @Test func duplicateCopiesBoundariesInsideTheBranchOnly() throws {
        var fixture = try GraphFixture(Self.outline)
        let inside = try Self.boundary(from: "A1", to: "A1", in: &fixture)
        let around = try Self.boundary(from: "A", to: "A", in: &fixture)
        let copyID = NodeID()

        try expectUndoAndRedo(DuplicateBranchCommand(nodeID: fixture["A"], copyID: copyID), on: &fixture)

        let copies = fixture.state.groups.values.filter { $0.id != inside && $0.id != around }
        #expect(copies.count == 1)
        #expect(copies.first?.parentNodeID == copyID)
        #expect(Self.members(around, in: fixture) == ["A"])
    }
}

import Foundation
import MindMapDomain
@testable import MindMapGraph
import Testing

/// Organization records as sync can leave them: partners missing, duplicates
/// from two offline devices, boundaries whose ends moved elsewhere.
@Suite("Repairing tags and boundaries")
struct OrganizationRepairTests {
    static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    struct Stored {
        let base: GraphFixture
        var tags: [MindTag] = []
        var links: [MindNodeTag] = []
        var groups: [MindGroup] = []

        init() throws {
            base = try GraphFixture("""
            Root
              A
              B
              C
            """)
        }

        var mapID: MapID { base.state.map.id }
        subscript(title: String) -> NodeID { base[title] }

        var state: GraphState {
            GraphState(
                map: base.state.map, nodes: base.state.nodes.values, edges: base.state.edges.values,
                tags: tags, nodeTags: links, groups: groups
            )
        }

        mutating func tag(_ name: String, shared: Bool = false, at seconds: TimeInterval) -> TagID {
            let tag = MindTag(mapID: shared ? nil : mapID, name: name, createdAt: start.addingTimeInterval(seconds))
            tags.append(tag)
            return tag.id
        }

        mutating func link(_ node: NodeID, _ tag: TagID, at seconds: TimeInterval) -> NodeTagID {
            let link = MindNodeTag(mapID: mapID, nodeID: node, tagID: tag, createdAt: start.addingTimeInterval(seconds))
            links.append(link)
            return link.id
        }

        mutating func group(first: NodeID?, last: NodeID?, parent: NodeID?, kind: GroupKind = .boundary) -> GroupID {
            let group = MindGroup(mapID: mapID, kind: kind, parentNodeID: parent, firstNodeID: first, lastNodeID: last, createdAt: start)
            groups.append(group)
            return group.id
        }
    }

    static func repaired(_ state: GraphState, after seconds: TimeInterval = 10) throws -> GraphRepairResult {
        let result = try GraphRepair.repair(state, now: start.addingTimeInterval(seconds))
        #expect(GraphValidator.validate(result.state).isEmpty)
        // A repaired graph needs no second repair.
        #expect(try GraphRepair.repair(result.state, now: start.addingTimeInterval(seconds)).changes.isEmpty)
        return result
    }

    @Test func deletesLinksWhoseTopicIsGone() throws {
        var stored = try Stored()
        let tag = stored.tag("Việc", at: 0)
        let dangling = stored.link(NodeID(), tag, at: 0)
        let kept = stored.link(stored["A"], tag, at: 0)

        #expect(GraphValidator.validate(stored.state) == [.danglingTagLink(dangling)])
        let result = try Self.repaired(stored.state)

        #expect(result.changes.deletedNodeTagIDs == [dangling])
        #expect(result.state.nodeTags.keys.sorted() == [kept])
    }

    @Test func keepsLinksWaitingForTheirTagUntilTheyExpire() throws {
        var stored = try Stored()
        let waiting = stored.link(stored["A"], TagID(), at: 0)

        let early = try Self.repaired(stored.state, after: 29 * 24 * 3600)
        #expect(early.changes.isEmpty)
        #expect(early.state.nodeTags[waiting] != nil)

        let late = try Self.repaired(stored.state, after: 31 * 24 * 3600)
        #expect(late.changes.deletedNodeTagIDs == [waiting])
    }

    @Test func mergesDuplicateMapTagsIntoTheOldest() throws {
        var stored = try Stored()
        let oldest = stored.tag("Việc", at: 0)
        let newer = stored.tag("VIỆC", at: 5)
        let differentMarks = stored.tag("viec", at: 6)
        let shared = stored.tag("việc", shared: true, at: 7)
        _ = stored.link(stored["A"], oldest, at: 1)
        _ = stored.link(stored["A"], newer, at: 0) // older link: this one is kept
        _ = stored.link(stored["B"], newer, at: 2)

        #expect(GraphValidator.validate(stored.state) == [.duplicateTag(newer)])
        let result = try Self.repaired(stored.state)

        #expect(Set(result.state.tags.keys) == [oldest, differentMarks, shared])
        #expect(result.state.tags(of: stored["A"]).map(\.id) == [oldest])
        #expect(result.state.nodeTags(of: stored["A"]).first?.createdAt == Self.start)
        #expect(result.state.tags(of: stored["B"]).map(\.id) == [oldest])
    }

    @Test func dropsDuplicateLinksKeepingTheOldest() throws {
        var stored = try Stored()
        let tag = stored.tag("Việc", at: 0)
        let oldest = stored.link(stored["A"], tag, at: 1)
        let duplicate = stored.link(stored["A"], tag, at: 2)

        #expect(GraphValidator.validate(stored.state) == [.duplicateTagLink(duplicate)])
        let result = try Self.repaired(stored.state)

        #expect(result.state.nodeTags.keys.sorted() == [oldest])
    }

    @Test func shrinksABoundaryToTheEndStillUnderItsParent() throws {
        var stored = try Stored()
        let id = stored.group(first: stored["A"], last: NodeID(), parent: stored["Root"])

        #expect(GraphValidator.validate(stored.state) == [.invalidGroup(id)])
        let result = try Self.repaired(stored.state)

        #expect(result.state.group(id)?.lastNodeID == stored["A"])
    }

    @Test func swapsEndsThatAreOutOfOrder() throws {
        var stored = try Stored()
        let id = stored.group(first: stored["C"], last: stored["A"], parent: stored["Root"])

        let result = try Self.repaired(stored.state)

        let group = try #require(result.state.group(id))
        #expect(result.state.members(of: group) == [stored["A"], stored["B"], stored["C"]])
    }

    @Test func deletesABoundaryWithNoMemberLeft() throws {
        var stored = try Stored()
        let noEnds = stored.group(first: NodeID(), last: nil, parent: stored["Root"])
        let noParent = stored.group(first: stored["A"], last: stored["A"], parent: NodeID())

        let result = try Self.repaired(stored.state)

        #expect(Set(result.changes.deletedGroupIDs) == [noEnds, noParent])
    }

    @Test func leavesKindsItDoesNotKnowAlone() throws {
        var stored = try Stored()
        _ = stored.group(first: nil, last: nil, parent: nil, kind: GroupKind(rawValue: "zone"))

        #expect(GraphValidator.validate(stored.state).isEmpty)
        #expect(try Self.repaired(stored.state).changes.isEmpty)
    }

    @Test func repairIsTheSameWhateverTheRecordOrder() throws {
        var stored = try Stored()
        let a = stored.tag("Việc", at: 3)
        let b = stored.tag("việc", at: 3)
        _ = stored.link(stored["A"], a, at: 0)
        _ = stored.link(stored["A"], b, at: 0)
        var reversed = stored
        reversed.tags.reverse()
        reversed.links.reverse()

        let one = try Self.repaired(stored.state)
        let other = try Self.repaired(reversed.state)

        #expect(one.state == other.state)
    }

    @Test func otherMapsRecordsAreDropped() throws {
        var stored = try Stored()
        let other = MapID()
        stored.tags.append(MindTag(mapID: other, name: "Elsewhere"))
        stored.links.append(MindNodeTag(mapID: other, nodeID: stored["A"], tagID: TagID()))
        stored.groups.append(MindGroup(mapID: other, parentNodeID: nil, firstNodeID: nil, lastNodeID: nil))

        let state = stored.state

        #expect(state.tags.isEmpty && state.nodeTags.isEmpty && state.groups.isEmpty)
    }
}

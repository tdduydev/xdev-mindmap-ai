import Foundation
import MindMapDomain
import MindMapGraph
@testable import MindMapInterchange
import Testing

@Suite("Map archive")
struct MapArchiveTests {
    @Test func everyFieldSurvivesARoundTrip() async throws {
        let graph = ArchiveFixture.everyField()

        let data = try await MapArchive.exportData(graph)
        let archive = try await MapArchive.decode(data)

        #expect(archive == MapArchive(graph))
        let restored = archive.graph
        #expect(restored.map == graph.map)
        #expect(restored.nodes == graph.nodes)
        #expect(restored.edges == graph.edges)
        #expect(restored.tags == graph.tags)
        #expect(restored.nodeTags == graph.nodeTags)
        #expect(restored.groups == graph.groups)
    }

    @Test func theSameMapWritesTheSameBytes() async throws {
        let graph = ArchiveFixture.everyField()

        let first = try await MapArchive.exportData(graph)
        let second = try await MapArchive.exportData(MapArchive.decode(first).graph)

        #expect(first == second)
    }

    @Test func unusedSharedTagsStayInTheLibrary() {
        var graph = ArchiveFixture.everyField()
        let unused = MindTag(mapID: nil, name: "Unused")
        graph = GraphState(
            map: graph.map, nodes: Array(graph.nodes.values), edges: Array(graph.edges.values),
            tags: Array(graph.tags.values) + [unused], nodeTags: Array(graph.nodeTags.values),
            groups: Array(graph.groups.values)
        )

        let archive = MapArchive(graph)

        #expect(!archive.tags.contains { $0.id == unused.id })
        #expect(archive.tags.contains { $0.name == "Shared" })
    }

    /// Compares each record with its copy minus the IDs, so a field added to
    /// the domain but not copied by `importedGraph` fails here.
    @Test func importingKeepsEverythingButTheIDs() async throws {
        let original = ArchiveFixture.everyField()
        let deleted = MindMap(
            id: original.map.id, title: original.map.title, rootNodeID: original.map.rootNodeID,
            createdAt: original.map.createdAt, updatedAt: original.map.updatedAt,
            isFavorite: original.map.isFavorite, theme: original.map.theme,
            layoutConfiguration: original.map.layoutConfiguration, deletedAt: .now
        )
        let graph = GraphState(
            map: deleted, nodes: Array(original.nodes.values), edges: Array(original.edges.values),
            tags: Array(original.tags.values), nodeTags: Array(original.nodeTags.values),
            groups: Array(original.groups.values)
        )

        let imported = try await MapArchive.decode(MapArchive.exportData(graph)).importedGraph()

        #expect(imported.map.id != graph.map.id)
        #expect(imported.map.deletedAt == nil)
        #expect(try fields(of: imported.map, without: ["id", "rootNodeID"])
            == fields(of: graph.map, without: ["id", "rootNodeID", "deletedAt"]))
        #expect(imported.root?.title == graph.root?.title)
        #expect(GraphValidator.validate(imported).isEmpty)

        let nodeKeys: Set = ["id", "mapID", "parentID"]
        for node in graph.nodes.values {
            let copy = try #require(imported.nodes.values.first { $0.title == node.title })
            #expect(copy.id != node.id)
            #expect(copy.parentID.flatMap { imported.node($0)?.title } == node.parentID.flatMap { graph.node($0)?.title })
            #expect(try fields(of: copy, without: nodeKeys) == fields(of: node, without: nodeKeys))
        }

        let edge = try #require(graph.edges.values.first)
        let edgeCopy = try #require(imported.edges.values.first)
        #expect(imported.node(edgeCopy.sourceNodeID)?.title == graph.node(edge.sourceNodeID)?.title)
        #expect(imported.node(edgeCopy.targetNodeID)?.title == graph.node(edge.targetNodeID)?.title)
        let edgeKeys: Set = ["id", "mapID", "sourceNodeID", "targetNodeID"]
        #expect(try fields(of: edgeCopy, without: edgeKeys) == fields(of: edge, without: edgeKeys))

        let group = try #require(graph.groups.values.first)
        let groupCopy = try #require(imported.groups.values.first)
        #expect(imported.members(of: groupCopy)?.compactMap { imported.node($0)?.title }
            == graph.members(of: group)?.compactMap { graph.node($0)?.title })
        let groupKeys: Set = ["id", "mapID", "parentNodeID", "firstNodeID", "lastNodeID"]
        #expect(try fields(of: groupCopy, without: groupKeys) == fields(of: group, without: groupKeys))

        let tagKeys: Set = ["id", "mapID"]
        for node in graph.nodes.values {
            let copy = try #require(imported.nodes.values.first { $0.title == node.title })
            #expect(imported.tags(of: copy.id).map(\.name) == graph.tags(of: node.id).map(\.name))
            for (tag, tagCopy) in zip(graph.tags(of: node.id), imported.tags(of: copy.id)) {
                #expect(try fields(of: tagCopy, without: tagKeys) == fields(of: tag, without: tagKeys))
            }
            for (link, linkCopy) in zip(graph.nodeTags(of: node.id), imported.nodeTags(of: copy.id)) {
                let linkKeys: Set = ["id", "mapID", "nodeID", "tagID"]
                #expect(try fields(of: linkCopy, without: linkKeys) == fields(of: link, without: linkKeys))
            }
        }
        // The library has no tag named "Shared", so it becomes the new map's tag.
        #expect(imported.tags.values.allSatisfy { $0.mapID == imported.map.id })
    }

    /// The summary topic gets a new ID like every topic, and the summary follows it.
    @Test func importingKeepsTheSummaryTopic() throws {
        let original = ArchiveFixture.everyField()
        let rootID = try #require(original.map.rootNodeID)
        let members = original.childIDs(of: rootID)
        let topic = MindNode(mapID: original.map.id, parentID: rootID, title: "Sum", sortOrder: 9)
        let summary = MindGroup(
            mapID: original.map.id, kind: .summary, parentNodeID: rootID,
            firstNodeID: members.first, lastNodeID: members.last, summaryNodeID: topic.id
        )
        let graph = GraphState(
            map: original.map, nodes: Array(original.nodes.values) + [topic], edges: [], groups: [summary]
        )

        let imported = MapArchive(graph).importedGraph()

        let copy = try #require(imported.groups.values.first)
        #expect(copy.summaryNodeID.flatMap { imported.node($0)?.title } == "Sum")
        #expect(GraphValidator.validate(imported).isEmpty)
    }

    @Test func aSharedTagJoinsTheLibraryTagWithTheSameKey() throws {
        let archive = MapArchive(ArchiveFixture.everyField())
        let library = MindTag(mapID: nil, name: "SHARED", color: .rose)

        let imported = archive.importedGraph(sharedTags: [library])

        #expect(imported.tags[library.id] == library)
        let tagged = try #require(imported.firstNode(titled: "Goals"))
        #expect(imported.tags(of: tagged.id).map(\.id).contains(library.id))
    }

    @Test func importingTwiceMakesTwoMaps() {
        let archive = MapArchive(ArchiveFixture.everyField())

        let first = archive.importedGraph()
        let second = archive.importedGraph()

        #expect(first.map.id != second.map.id)
        #expect(Set(first.nodes.keys).isDisjoint(with: second.nodes.keys))
    }

    /// A version 1 file as the first release writes it, kept as text so a
    /// change to the domain types that cannot read it fails here. It leaves
    /// out every optional field, as a file from before they existed would.
    @Test func aVersion1FileStillOpens() async throws {
        let archive = try await MapArchive.decode(Data(ArchiveFixture.version1.utf8))

        let graph = archive.graph
        #expect(graph.map.title == "Kế hoạch")
        #expect(graph.map.theme == .graphite)
        #expect(graph.root?.title == "Kế hoạch")
        #expect(graph.nodes.count == 2)
        let child = try #require(graph.firstNode(titled: "Mục tiêu"))
        #expect(child.taskState == .done)
        #expect(child.dueDate == CalendarDay(year: 2026, month: 10, day: 2))
        #expect(child.color == nil)
        #expect(graph.tags(of: child.id).map(\.name) == ["Việc"])
        #expect(GraphValidator.validate(graph).isEmpty)
    }

    @Test func fieldsANewerBuildAddsAreSkipped() async throws {
        let text = ArchiveFixture.version1.replacingOccurrences(
            of: "\"title\" : \"Mục tiêu\"",
            with: "\"title\" : \"Mục tiêu\", \"position\" : { \"x\" : 1, \"y\" : 2 }"
        )

        let archive = try await MapArchive.decode(Data(text.utf8))

        #expect(archive.nodes.contains { $0.title == "Mục tiêu" })
    }

    @Test func aNewerVersionIsRefused() async throws {
        let text = ArchiveFixture.version1.replacingOccurrences(of: "\"version\" : 1", with: "\"version\" : 2")

        await #expect(throws: MapArchiveError.newerVersion(2)) {
            try await MapArchive.decode(Data(text.utf8))
        }
    }

    @Test(arguments: ["", "not json", "{}", #"{"format": "com.example.other", "version": 1}"#, "[1, 2]"])
    func otherFilesAreNotArchives(_ text: String) async throws {
        #expect(!MapArchive.isArchive(Data(text.utf8)))
        await #expect(throws: MapArchiveError.notAnArchive) {
            try await MapArchive.decode(Data(text.utf8))
        }
    }

    @Test func aDamagedArchiveSaysSo() async throws {
        let text = ArchiveFixture.version1.replacingOccurrences(of: "\"dueDate\" : \"2026-10-02\"", with: "\"dueDate\" : \"tomorrow\"")

        #expect(MapArchive.isArchive(Data(text.utf8)))
        await #expect(throws: MapArchiveError.damaged) {
            try await MapArchive.decode(Data(text.utf8))
        }
    }

    private func fields(of value: some Encodable, without keys: Set<String>) throws -> NSDictionary {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
        var dictionary = try #require(object as? [String: Any])
        for key in keys { dictionary[key] = nil }
        return dictionary as NSDictionary
    }
}

enum ArchiveFixture {
    /// A map that sets every stored field to something other than its default.
    static func everyField() -> GraphState {
        let mapID = MapID()
        let rootID = NodeID()
        let created = Date(timeIntervalSinceReferenceDate: 800_000_000.123_456)
        let edited = created.addingTimeInterval(3_600.5)
        let map = MindMap(
            id: mapID, title: "Plan", rootNodeID: rootID, createdAt: created, updatedAt: edited,
            isFavorite: true, theme: .xdevBlue
        )
        let root = MindNode(id: rootID, mapID: mapID, parentID: nil, title: "Plan", createdAt: created)
        let goals = MindNode(
            mapID: mapID, parentID: rootID, title: "Goals", note: "Why\n> it matters", sortOrder: 1.5,
            isCollapsed: true, metadata: NodeMetadata(origin: .ai), createdAt: created, updatedAt: edited,
            color: .violet, symbol: "star.fill", taskState: .done, priority: .high,
            startDate: CalendarDay(year: 2026, month: 1, day: 31), dueDate: CalendarDay(year: 2026, month: 2, day: 28),
            link: TopicLink(string: "https://example.com/goals"), callout: "Check with finance"
        )
        let aside = MindNode(
            mapID: mapID, parentID: nil, title: "Aside", createdAt: created, position: TopicPosition(x: -240.25, y: 88)
        )
        let risks = MindNode(
            mapID: mapID, parentID: rootID, title: "Risks", sortOrder: 2,
            metadata: NodeMetadata(origin: .imported), createdAt: created,
            color: TopicColor(rawValue: "ultraviolet"), symbol: "🚀", taskState: TaskState(rawValue: "blocked"),
            priority: TaskPriority(rawValue: 7)
        )
        let detail = MindNode(mapID: mapID, parentID: goals.id, title: "Detail", sortOrder: -1, createdAt: created)
        let edge = MindEdge(
            mapID: mapID, sourceNodeID: goals.id, targetNodeID: risks.id, edgeType: .reference,
            label: "blocks", createdAt: created, updatedAt: edited,
            lineStyle: .dashed, arrowHeads: .both, color: .amber
        )
        let mapTag = MindTag(mapID: mapID, name: "Việc", color: .green, symbol: "flag", sortOrder: 3, createdAt: created, updatedAt: edited)
        let sharedTag = MindTag(mapID: nil, name: "Shared", color: .teal, sortOrder: 1, createdAt: created)
        let links = [
            MindNodeTag(mapID: mapID, nodeID: goals.id, tagID: mapTag.id, origin: .ai, createdAt: created),
            MindNodeTag(mapID: mapID, nodeID: goals.id, tagID: sharedTag.id, createdAt: edited),
        ]
        let group = MindGroup(
            mapID: mapID, kind: .boundary, parentNodeID: rootID, firstNodeID: goals.id, lastNodeID: risks.id,
            title: "Scope", color: .rose, origin: .ai, createdAt: created, updatedAt: edited
        )
        return GraphState(
            map: map, nodes: [root, goals, risks, detail, aside], edges: [edge],
            tags: [mapTag, sharedTag], nodeTags: links, groups: [group]
        )
    }

    static let version1 = """
    {
      "edges" : [],
      "format" : "asia.xdev.mindmapai.map",
      "groups" : [],
      "map" : {
        "createdAt" : 800000000,
        "id" : "6A1B2C3D-0000-4000-8000-000000000001",
        "isFavorite" : false,
        "layoutConfiguration" : { "style" : "horizontalTree" },
        "rootNodeID" : "6A1B2C3D-0000-4000-8000-000000000010",
        "theme" : "graphite",
        "title" : "Kế hoạch",
        "updatedAt" : 800000100
      },
      "nodeTags" : [
        {
          "createdAt" : 800000000,
          "id" : "6A1B2C3D-0000-4000-8000-000000000030",
          "mapID" : "6A1B2C3D-0000-4000-8000-000000000001",
          "nodeID" : "6A1B2C3D-0000-4000-8000-000000000011",
          "origin" : "user",
          "tagID" : "6A1B2C3D-0000-4000-8000-000000000020",
          "updatedAt" : 800000000
        }
      ],
      "nodes" : [
        {
          "createdAt" : 800000000,
          "id" : "6A1B2C3D-0000-4000-8000-000000000010",
          "isCollapsed" : false,
          "mapID" : "6A1B2C3D-0000-4000-8000-000000000001",
          "metadata" : { "origin" : "user" },
          "nodeType" : "topic",
          "sortOrder" : 0,
          "title" : "Kế hoạch",
          "updatedAt" : 800000000
        },
        {
          "createdAt" : 800000000,
          "dueDate" : "2026-10-02",
          "id" : "6A1B2C3D-0000-4000-8000-000000000011",
          "isCollapsed" : false,
          "mapID" : "6A1B2C3D-0000-4000-8000-000000000001",
          "metadata" : { "origin" : "user" },
          "nodeType" : "topic",
          "parentID" : "6A1B2C3D-0000-4000-8000-000000000010",
          "sortOrder" : 1,
          "taskState" : "done",
          "title" : "Mục tiêu",
          "updatedAt" : 800000000
        }
      ],
      "tags" : [
        {
          "createdAt" : 800000000,
          "id" : "6A1B2C3D-0000-4000-8000-000000000020",
          "mapID" : "6A1B2C3D-0000-4000-8000-000000000001",
          "name" : "Việc",
          "sortOrder" : 0,
          "updatedAt" : 800000000
        }
      ],
      "version" : 1
    }
    """
}

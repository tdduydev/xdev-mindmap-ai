import Foundation
import MindMapDomain
import MindMapGraph
import MindMapPersistence
@testable import MindMapQuery
import Synchronization
import Testing

@Suite("Map queries")
struct MapQueriesTests {
    /// Stands in for the app's open editors: graphs here win over the store.
    final class OpenGraphs: GraphSource {
        let repository: any MapRepository
        let open = Mutex<[MapID: GraphState]>([:])

        init(repository: any MapRepository) {
            self.repository = repository
        }

        func graph(for mapID: MapID) async throws -> GraphState? {
            if let live = open.withLock({ $0[mapID] }) { return live }
            return try await repository.loadGraph(for: mapID)
        }

        func openMapIDs() async -> Set<MapID> {
            Set(open.withLock { $0.keys })
        }
    }

    let repository: SwiftDataMapRepository
    let graphs: OpenGraphs
    let queries: MapQueries

    init() throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
        graphs = OpenGraphs(repository: repository)
        queries = MapQueries(repository: repository, graphs: graphs)
    }

    // MARK: Fixtures

    /// A map from (title, note, children) rows; IDs by title for the asserts.
    struct Built {
        var state: GraphState
        var ids: [String: NodeID]
        var mapID: MapID { state.map.id }
    }

    indirect enum Row {
        case topic(String, note: String? = nil, [Row] = [])
    }

    static func build(_ title: String, edited: Date = .now, _ rows: [Row] = []) -> Built {
        let mapID = MapID()
        let rootID = NodeID()
        var nodes = [MindNode(id: rootID, mapID: mapID, parentID: nil, title: title, createdAt: edited)]
        var ids = [title: rootID]
        func add(_ rows: [Row], under parentID: NodeID) {
            for (index, row) in rows.enumerated() {
                guard case let .topic(text, note, children) = row else { continue }
                let id = NodeID()
                nodes.append(MindNode(
                    id: id, mapID: mapID, parentID: parentID, title: text, note: note,
                    sortOrder: Double(index), createdAt: edited
                ))
                ids[text] = id
                add(children, under: id)
            }
        }
        add(rows, under: rootID)
        let map = MindMap(id: mapID, title: title, rootNodeID: rootID, createdAt: edited)
        return Built(state: GraphState(map: map, nodes: nodes, edges: []), ids: ids)
    }

    @discardableResult
    func store(_ built: Built) async throws -> Built {
        try await repository.create(built.state)
        return built
    }

    static let plan = build("Kế hoạch dự án", edited: Date(timeIntervalSince1970: 2_000), [
        .topic("Thiết kế", note: "Đường dẫn chính\nPhác thảo giao diện đầu tiên", [
            .topic("Màn hình đăng nhập"),
            .topic("Đặt lịch"),
        ]),
        .topic("Ngân sách", note: "Chi phí đi lại và thiết kế bao bì"),
        .topic("Release", note: "Ship to the App Store"),
    ])

    static let trip = build("Trip to Hanoi", edited: Date(timeIntervalSince1970: 1_000), [
        .topic("Flights", note: "Book the design conference first"),
        .topic("Design museum"),
    ])

    // MARK: Search

    @Test func vietnameseSearchIgnoresMarksCaseAndĐ() async throws {
        let plan = try await store(Self.plan)

        for text in ["thiet ke", "THIẾT KẾ", "ke thiet", "Thiết Kế"] {
            let hits = try await queries.search(text, limit: 10)
            #expect(hits.first?.ref == TopicRef(mapID: plan.mapID, nodeID: plan.ids["Thiết kế"]!), "\(text)")
            #expect(hits.first?.match == .title)
        }
        // "đ" has no decomposition; "d" must still find it, and the other way round.
        #expect(try await queries.search("dat lich", limit: 10).map(\.title) == ["Đặt lịch"])
        #expect(try await queries.search("đặt", limit: 10).map(\.title) == ["Đặt lịch"])
        #expect(try await queries.search("duong dan", limit: 10).map(\.title) == ["Thiết kế"])
    }

    @Test func englishSearchFindsTitlesBeforeNotesAcrossMaps() async throws {
        try await store(Self.plan)
        try await store(Self.trip)

        let hits = try await queries.search("design", limit: 10)

        #expect(hits.map(\.title) == ["Design museum", "Flights"])
        #expect(hits.map(\.match) == [.title, .note])
        #expect(hits[1].excerpt == "Book the design conference first")
        #expect(hits[0].path == ["Trip to Hanoi"])
        #expect(hits[0].mapTitle == "Trip to Hanoi")
    }

    @Test func titleHitsRankFirstThenMapsByLastEdit() async throws {
        let plan = try await store(Self.plan)
        let trip = try await store(Self.trip)

        let hits = try await queries.search("thiet", limit: 10)

        // The title match comes first even though the note match sits higher in the outline.
        #expect(hits.map(\.title) == ["Thiết kế", "Ngân sách"])
        #expect(hits.map(\.ref.mapID) == [plan.mapID, plan.mapID])
        #expect(!hits.contains { $0.ref.mapID == trip.mapID })
        #expect(hits[1].excerpt == "Chi phí đi lại và thiết kế bao bì")
        #expect(hits[0].path == ["Kế hoạch dự án"])
    }

    @Test func searchCanStayInOneMapAndHonoursTheLimit() async throws {
        try await store(Self.plan)
        let trip = try await store(Self.trip)

        let inTrip = try await queries.search("design", in: trip.mapID, limit: 10)
        #expect(Set(inTrip.map(\.ref.mapID)) == [trip.mapID])
        #expect(try await queries.search("design", limit: 1).map(\.title) == ["Design museum"])
        #expect(try await queries.search("   ", limit: 10).isEmpty)
        #expect(try await queries.search("design", limit: 0).isEmpty)
        await #expect(throws: MapQueryError.mapNotFound) {
            try await queries.search("design", in: MapID(), limit: 10)
        }
    }

    @Test func pathRunsFromTheCentralTopic() async throws {
        let plan = try await store(Self.plan)
        let hit = try #require(try await queries.search("dang nhap", limit: 5).first)
        #expect(hit.ref.nodeID == plan.ids["Màn hình đăng nhập"])
        #expect(hit.path == ["Kế hoạch dự án", "Thiết kế"])
    }

    @Test func longNoteExcerptIsShortenedAroundTheMatch() {
        let note = String(repeating: "lorem ipsum ", count: 30) + "Tiền thuê kho" + String(repeating: " dolor", count: 40)
        let excerpt = MapQueries.excerpt(of: note, for: .init("tien thue"))
        #expect(excerpt.contains("Tiền thuê kho"))
        #expect(excerpt.hasPrefix("…") && excerpt.hasSuffix("…"))
        #expect(excerpt.count <= MapQueries.excerptLength + 2)
    }

    // MARK: Recently Deleted

    @Test func deletedMapsAreNeverReturned() async throws {
        let plan = try await store(Self.plan)
        let trip = try await store(Self.trip)
        try await repository.moveToRecentlyDeleted(trip.mapID, at: .now)

        #expect(try await queries.maps(matching: nil, limit: 10).map(\.mapID) == [plan.mapID])
        #expect(try await queries.search("design", limit: 10).isEmpty)
        #expect(try await queries.topic(TopicRef(mapID: trip.mapID, nodeID: trip.ids["Flights"]!)) == nil)
        await #expect(throws: MapQueryError.mapNotFound) {
            try await queries.outline(of: trip.mapID, limit: .characters(1_000))
        }
        await #expect(throws: MapQueryError.mapNotFound) {
            try await queries.search("design", in: trip.mapID, limit: 10)
        }
    }

    @Test func anOpenCopyOfADeletedMapIsLeftOutToo() async throws {
        // The editor's copy still has deletedAt nil; the store knows better.
        let trip = try await store(Self.trip)
        graphs.open.withLock { $0[trip.mapID] = trip.state }
        try await repository.moveToRecentlyDeleted(trip.mapID, at: .now)

        #expect(try await queries.maps(matching: nil, limit: 10).isEmpty)
        #expect(try await queries.search("flights", limit: 10).isEmpty)
    }

    // MARK: Live state

    @Test func openMapsAreReadFromTheirLiveState() async throws {
        let trip = try await store(Self.trip)
        var live = trip.state
        let museum = try #require(trip.ids["Design museum"])
        var renamed = try #require(live.node(museum))
        renamed.title = "Văn Miếu"
        renamed.updatedAt = Date(timeIntervalSince1970: 3_000)
        live = GraphState(
            map: MindMap(id: trip.mapID, title: "Chuyến đi Hà Nội", rootNodeID: live.map.rootNodeID,
                         createdAt: live.map.createdAt, updatedAt: renamed.updatedAt),
            nodes: live.nodes.values.map { $0.id == museum ? renamed : $0 } + [
                MindNode(mapID: trip.mapID, parentID: live.map.rootNodeID, title: "Phở", sortOrder: 9),
            ],
            edges: []
        )
        try await store(Self.plan)
        graphs.open.withLock { $0[trip.mapID] = live }

        // Not saved yet, so only the live graph knows these words.
        #expect(try await queries.search("van mieu", limit: 10).map(\.ref.nodeID) == [museum])
        #expect(try await queries.search("pho", limit: 10).map(\.title) == ["Phở"])
        #expect(try await queries.search("museum", limit: 10).isEmpty)
        #expect(try await queries.topic(TopicRef(mapID: trip.mapID, nodeID: museum))?.title == "Văn Miếu")

        let listings = try await queries.maps(matching: nil, limit: 10)
        #expect(listings.map(\.title) == ["Chuyến đi Hà Nội", "Kế hoạch dự án"])
        #expect(listings.first?.topicCount == 4)
        #expect(try await queries.maps(matching: "chuyen di", limit: 10).map(\.mapID) == [trip.mapID])
    }

    // MARK: Maps

    @Test func mapsListMostRecentlyEditedFirstWithSizes() async throws {
        let plan = try await store(Self.plan)
        let trip = try await store(Self.trip)

        let listings = try await queries.maps(matching: nil, limit: 10)
        #expect(listings.map(\.mapID) == [plan.mapID, trip.mapID])
        #expect(listings.map(\.topicCount) == [6, 3])
        #expect(try await queries.maps(matching: "ke hoach", limit: 10).map(\.mapID) == [plan.mapID])
        #expect(try await queries.maps(matching: "HANOI", limit: 10).map(\.mapID) == [trip.mapID])
        #expect(try await queries.maps(matching: "  ", limit: 1).map(\.mapID) == [plan.mapID])
        #expect(try await queries.maps(matching: nil, limit: 0).isEmpty)
    }

    // MARK: Outline

    @Test func outlineReadsTheWholeMapInOrder() async throws {
        let plan = try await store(Self.plan)

        let outline = try await queries.outline(of: plan.mapID, limit: .characters(10_000))

        #expect(outline.mapTitle == "Kế hoạch dự án")
        #expect(outline.topics.map(\.title) == [
            "Kế hoạch dự án", "Thiết kế", "Màn hình đăng nhập", "Đặt lịch", "Ngân sách", "Release",
        ])
        #expect(outline.topics.map(\.depth) == [0, 1, 2, 2, 1, 1])
        #expect(outline.topics[1].note == "Đường dẫn chính\nPhác thảo giao diện đầu tiên")
        #expect(outline.topics[1].childCount == 2)
        #expect(outline.omittedTopicCount == 0 && outline.deeperTopicCount == 0)
    }

    @Test func outlineIncludesCollapsedBranches() async throws {
        var plan = Self.plan
        let design = try #require(plan.ids["Thiết kế"])
        var node = try #require(plan.state.node(design))
        node.isCollapsed = true
        plan.state = GraphState(map: plan.state.map, nodes: plan.state.nodes.values.map { $0.id == design ? node : $0 }, edges: [])
        try await store(plan)

        let outline = try await queries.outline(of: plan.mapID, limit: .characters(10_000))
        #expect(outline.topics.contains { $0.title == "Màn hình đăng nhập" })
    }

    @Test func outlineOfABranchToADepthWithoutNotes() async throws {
        let plan = try await store(Self.plan)

        let branch = try await queries.outline(
            of: plan.mapID, branch: plan.ids["Thiết kế"], depth: 0, includeNotes: false, limit: .characters(10_000)
        )
        #expect(branch.topics.map(\.title) == ["Thiết kế"])
        #expect(branch.topics[0].note == nil)
        #expect(branch.deeperTopicCount == 2)

        let top = try await queries.outline(of: plan.mapID, depth: 1, limit: .characters(10_000))
        #expect(top.topics.map(\.title) == ["Kế hoạch dự án", "Thiết kế", "Ngân sách", "Release"])
        #expect(top.deeperTopicCount == 2)

        await #expect(throws: MapQueryError.topicNotFound) {
            try await queries.outline(of: plan.mapID, branch: NodeID(), limit: .characters(10_000))
        }
    }

    @Test func outlineStopsAtTheLimitAndCountsWhatIsLeft() async throws {
        let plan = try await store(Self.plan)
        // Root (14) + "Thiết kế" (8) + its note (44) = 66; the next topic does not fit.
        let limit = TextLimit.characters(70)

        let outline = try await queries.outline(of: plan.mapID, limit: limit)

        #expect(outline.topics.map(\.title) == ["Kế hoạch dự án", "Thiết kế"])
        #expect(outline.omittedTopicCount == 4)
        let used = outline.topics.reduce(0) { $0 + limit.cost($1.title) + limit.cost($1.note ?? "") }
        #expect(used <= limit.budget)
    }

    @Test func perTopicCostCountsAgainstTheLimit() async throws {
        let plan = try await store(Self.plan)
        let outline = try await queries.outline(
            of: plan.mapID, includeNotes: false, limit: .characters(60, perTopic: 40)
        )
        // Each topic costs 40 plus its title, so only the central topic fits.
        #expect(outline.topics.count == 1)
        #expect(outline.omittedTopicCount == 5)
    }

    @Test func aFirstTopicWithAHugeNoteIsCutNotDropped() async throws {
        let long = String(repeating: "Ghi chú rất dài. ", count: 200)
        let map = try await store(Self.build("Notes", [.topic("Big", note: long, [.topic("Child")])]))

        let outline = try await queries.outline(of: map.mapID, branch: map.ids["Big"], limit: .characters(100))

        let first = try #require(outline.topics.first)
        #expect(outline.topics.count == 1)
        #expect(first.isNoteCut)
        #expect(long.hasPrefix(first.note ?? "x"))
        #expect(3 + (first.note?.count ?? 0) <= 100)
        #expect(outline.omittedTopicCount == 1)
    }

    @Test func tokenLimitUsesTheCallersMeasure() async throws {
        let plan = try await store(Self.plan)
        // One token per character for Vietnamese, as the chat's estimator counts it.
        let tokens = TextLimit(budget: 30, perTopic: 3) { $0.count }
        let outline = try await queries.outline(of: plan.mapID, includeNotes: false, limit: tokens)
        #expect(outline.topics.map(\.title) == ["Kế hoạch dự án", "Thiết kế"])
    }

    // MARK: Topic

    @Test func topicDetailHasPathChildrenTagsTaskAndLinks() async throws {
        var plan = Self.plan
        let design = try #require(plan.ids["Thiết kế"])
        let budget = try #require(plan.ids["Ngân sách"])
        let tag = MindTag(mapID: plan.mapID, name: "Ưu tiên")
        var node = try #require(plan.state.node(design))
        node.taskState = .open
        node.priority = .high
        node.dueDate = CalendarDay(year: 2026, month: 10, day: 31)
        plan.state = GraphState(
            map: plan.state.map,
            nodes: plan.state.nodes.values.map { $0.id == design ? node : $0 },
            edges: [MindEdge(mapID: plan.mapID, sourceNodeID: budget, targetNodeID: design, label: "phụ thuộc")],
            tags: [tag],
            nodeTags: [MindNodeTag(mapID: plan.mapID, nodeID: design, tagID: tag.id)]
        )
        try await store(plan)

        let detail = try #require(try await queries.topic(TopicRef(mapID: plan.mapID, nodeID: design)))

        #expect(detail.title == "Thiết kế")
        #expect(detail.mapTitle == "Kế hoạch dự án")
        #expect(detail.note == "Đường dẫn chính\nPhác thảo giao diện đầu tiên")
        #expect(detail.path.map(\.title) == ["Kế hoạch dự án"])
        #expect(detail.children.map(\.title) == ["Màn hình đăng nhập", "Đặt lịch"])
        #expect(detail.tags == ["Ưu tiên"])
        #expect(detail.taskState == .open && detail.priority == .high)
        #expect(detail.dueDate == CalendarDay(year: 2026, month: 10, day: 31))
        #expect(detail.crossLinks == [.init(topic: .init(nodeID: budget, title: "Ngân sách"), label: "phụ thuộc", direction: .incoming)])
        #expect(try await queries.topic(TopicRef(mapID: plan.mapID, nodeID: NodeID())) == nil)
    }
}

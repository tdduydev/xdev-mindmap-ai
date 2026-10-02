import Foundation
import MindMapDomain
@testable import MindMapMCP
import Testing

@Suite("MCP map tools")
struct MapToolsTests {
    let harness: MCPHarness

    init() throws {
        harness = try MCPHarness()
    }

    func storePlan() async throws -> MCPHarness.Built {
        try await harness.store("Kế hoạch dự án", edited: Date(timeIntervalSince1970: 2_000), [
            .topic("Thiết kế", note: "Phác thảo giao diện đầu tiên\nĐường dẫn chính", [
                .topic("Màn hình đăng nhập"),
                .topic("Đặt lịch"),
            ]),
            .topic("Ngân sách", note: "Chi phí đi lại"),
        ])
    }

    // MARK: list_maps

    @Test func listMapsShowsIDsCountsAndNewestFirst() async throws {
        let plan = try await storePlan()
        let trip = try await harness.store("Trip to Hanoi", edited: Date(timeIntervalSince1970: 1_000), [.topic("Flights")])

        let (text, structured, isError) = try await harness.call("list_maps")
        #expect(!isError)
        #expect(text.hasPrefix("2 maps, most recently edited first:"))
        #expect(text.contains("- Kế hoạch dự án (map_id: \(plan.mapID), 5 topics, edited 1970-01-01T00:33:20Z)"))
        let ids = structured?["maps"]?.arrayValue?.compactMap { $0["map_id"]?.stringValue }
        #expect(ids == [plan.mapID.description, trip.mapID.description])

        let filtered = try await harness.call("list_maps", ["query": "ke hoach", "limit": 1])
        #expect(filtered.structured?["maps"]?.arrayValue?.count == 1)
        #expect(try await harness.call("list_maps", ["query": "nothing like it"]).text.hasPrefix("No map title matches"))
    }

    @Test func recentlyDeletedMapsAreNotReachable() async throws {
        let plan = try await storePlan()
        try await harness.repository.moveToRecentlyDeleted(plan.mapID, at: .now)

        #expect(try await harness.call("list_maps").text == "There are no maps yet.")
        let outline = try await harness.call("get_map", ["map_id": .string(plan.mapID.description)])
        #expect(outline.isError)
        #expect(outline.text == MapTools.mapNotFound)
        #expect(try await harness.call("search", ["query": "thiet ke"]).text.hasPrefix("No topic matches"))
    }

    // MARK: get_map

    @Test func getMapIsAnOutlineWithTopicIDs() async throws {
        let plan = try await storePlan()
        let (text, structured, isError) = try await harness.call("get_map", ["map_id": .string(plan.mapID.description)])
        #expect(!isError)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines[0] == "# Kế hoạch dự án (map_id: \(plan.mapID))")
        #expect(lines.contains("- Kế hoạch dự án <!-- topic_id: \(plan.ids["Kế hoạch dự án"]!) -->"))
        #expect(lines.contains("  - Thiết kế <!-- topic_id: \(plan.ids["Thiết kế"]!) -->"))
        #expect(lines.contains("    Phác thảo giao diện đầu tiên"))
        #expect(lines.contains("    - Đặt lịch <!-- topic_id: \(plan.ids["Đặt lịch"]!) -->"))
        #expect(structured?["topics"]?.arrayValue?.count == 5)
        #expect(structured?["topics"]?.arrayFirst?["child_count"] == 2)
    }

    @Test func getMapReadsOneBranchToADepthWithoutNotes() async throws {
        let plan = try await storePlan()
        let (text, structured, _) = try await harness.call("get_map", [
            "map_id": .string(plan.mapID.description),
            "topic_id": .string(plan.ids["Thiết kế"]!.description),
            "depth": 0,
            "include_notes": false,
        ])
        #expect(structured?["topics"]?.arrayValue?.count == 1)
        #expect(!text.contains("Phác thảo"))
        #expect(text.contains("2 topics below depth 0 not shown."))
    }

    @Test func aLargeMapIsCutAndSaysHowToReadTheRest() async throws {
        let rows = (1...400).map { MCPHarness.Row.topic("Topic number \($0)", note: String(repeating: "note ", count: 20)) }
        let big = try await harness.store("Big", rows)
        let (text, structured, _) = try await harness.call("get_map", ["map_id": .string(big.mapID.description)])
        #expect(text.count <= 20_000)
        let omitted = try #require(structured?["omitted_topic_count"]?.intValue)
        #expect(omitted > 0)
        #expect(text.contains("\(omitted) more topics did not fit. Call get_map with topic_id"))
    }

    @Test func theOutputLimitIsConfigurable() async throws {
        let harness = try MCPHarness { $0.outputLimit = 2_000 }
        let rows = (1...200).map { MCPHarness.Row.topic("Topic number \($0)") }
        let big = try await harness.store("Big", rows)
        let (text, _, _) = try await harness.call("get_map", ["map_id": .string(big.mapID.description)])
        #expect(text.count <= 2_000)
    }

    @Test func badArgumentsAreToolErrorsTheModelCanFix() async throws {
        let plan = try await storePlan()
        let missing = try await harness.call("get_map")
        #expect(missing.isError)
        #expect(missing.text.contains("map_id is required"))

        let malformed = try await harness.call("get_map", ["map_id": "not-an-id"])
        #expect(malformed.isError)
        #expect(malformed.text.contains("map_id must be an ID"))

        let wrongType = try await harness.call("get_map", ["map_id": .string(plan.mapID.description), "depth": "two"])
        #expect(wrongType.isError)
        #expect(wrongType.text == "depth must be a whole number.")

        let unknownBranch = try await harness.call("get_map", ["map_id": .string(plan.mapID.description), "topic_id": .string(UUID().uuidString)])
        #expect(unknownBranch.text == MapTools.topicNotFound)

        #expect(try await harness.call("search", ["query": "  "]).isError)
    }

    // MARK: search

    @Test func searchFoldsVietnameseAndGivesPathsAndIDs() async throws {
        let plan = try await storePlan()
        let (text, structured, isError) = try await harness.call("search", ["query": "dat lich"])
        #expect(!isError)
        #expect(text.contains("1. Đặt lịch (map: Kế hoạch dự án; map_id: \(plan.mapID), topic_id: \(plan.ids["Đặt lịch"]!))"))
        #expect(text.contains("   Path: Kế hoạch dự án › Thiết kế"))
        #expect(structured?["hits"]?.arrayFirst?["match"] == "title")

        let note = try await harness.call("search", ["query": "chi phi"])
        #expect(note.text.contains("   Note: Chi phí đi lại"))
        #expect(note.structured?["hits"]?.arrayFirst?["excerpt"] == "Chi phí đi lại")

        let inOtherMap = try await harness.call("search", ["query": "dat lich", "map_id": .string(UUID().uuidString)])
        #expect(inOtherMap.isError)
    }

    // MARK: get_topic

    @Test func getTopicHasEverything() async throws {
        let plan = try await harness.store("Kế hoạch dự án", [
            .topic("Thiết kế", note: "Phác thảo giao diện đầu tiên\nĐường dẫn chính", [.topic("Màn hình đăng nhập"), .topic("Đặt lịch")]),
            .topic("Ngân sách"),
        ]) { nodes, ids, mapID in
            let index = nodes.firstIndex { $0.id == ids["Thiết kế"] }!
            nodes[index].taskState = .open
            nodes[index].priority = .high
            nodes[index].dueDate = CalendarDay(year: 2026, month: 10, day: 31)
            return [MindEdge(mapID: mapID, sourceNodeID: ids["Thiết kế"]!, targetNodeID: ids["Ngân sách"]!, label: "costs")]
        }
        let design = plan.ids["Thiết kế"]!

        let (text, structured, isError) = try await harness.call("get_topic", [
            "map_id": .string(plan.mapID.description), "topic_id": .string(design.description),
        ])
        #expect(!isError)
        #expect(text.hasPrefix("# Thiết kế"))
        #expect(text.contains("- Path: Kế hoạch dự án"))
        #expect(text.contains("- Task: open"))
        #expect(text.contains("- Priority: high"))
        #expect(text.contains("- Due: 2026-10-31"))
        #expect(text.contains("## Note\n\nPhác thảo giao diện đầu tiên\nĐường dẫn chính"))
        #expect(text.contains("- Màn hình đăng nhập (topic_id: \(plan.ids["Màn hình đăng nhập"]!))"))
        #expect(text.contains("- → Ngân sách (topic_id: \(plan.ids["Ngân sách"]!)) — costs"))
        #expect(structured?["cross_links"]?.arrayFirst?["direction"] == "outgoing")
        #expect(structured?["children"]?.arrayValue?.count == 2)
    }

    @Test func getTopicTellsAMissingMapFromAMissingTopic() async throws {
        let plan = try await storePlan()
        let missingTopic = try await harness.call("get_topic", ["map_id": .string(plan.mapID.description), "topic_id": .string(UUID().uuidString)])
        #expect(missingTopic.text == MapTools.topicNotFound)
        let missingMap = try await harness.call("get_topic", ["map_id": .string(UUID().uuidString), "topic_id": .string(UUID().uuidString)])
        #expect(missingMap.text == MapTools.mapNotFound)
    }

    @Test func aGiantNoteIsCutToTheLimit() async throws {
        let harness = try MCPHarness { $0.outputLimit = 1_000 }
        let map = try await harness.store("Notes", [.topic("Long", note: String(repeating: "word ", count: 2_000))])
        let (text, structured, _) = try await harness.call("get_topic", [
            "map_id": .string(map.mapID.description), "topic_id": .string(map.ids["Long"]!.description),
        ])
        #expect(text.count <= 1_000)
        #expect(text.hasSuffix("… (cut at 1000 characters)"))
        #expect(structured?["note"]?.stringValue?.count == 10_000, "structured content is never cut mid-JSON")
    }
}

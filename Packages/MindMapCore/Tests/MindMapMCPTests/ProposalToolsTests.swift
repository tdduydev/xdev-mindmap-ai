import Foundation
import MindMapDomain
@testable import MindMapMCP
import Testing

/// Keeps what the server hands over, and answers as told.
private actor RecordingReceiver: MCPProposalReceiver {
    private(set) var received: [MCPProposal] = []
    var outcome: MCPProposalOutcome

    init(outcome: MCPProposalOutcome = .shown) {
        self.outcome = outcome
    }

    func receive(_ proposal: MCPProposal) async -> MCPProposalOutcome {
        received.append(proposal)
        return outcome
    }

    func answer(_ outcome: MCPProposalOutcome) { self.outcome = outcome }
}

@Suite("MCP propose_topics")
struct ProposalToolsTests {
    private let receiver = RecordingReceiver()
    private let harness: MCPHarness

    init() throws {
        harness = try MCPHarness(proposals: receiver)
    }

    private func storePlan() async throws -> MCPHarness.Built {
        try await harness.store("Kế hoạch dự án", [.topic("Thiết kế", [.topic("Màn hình đăng nhập")])])
    }

    private func arguments(_ built: MCPHarness.Built, under title: String, _ topics: JSONValue) -> [String: JSONValue] {
        ["map_id": .string(built.mapID.description), "parent_topic_id": .string(built.ids[title]!.description), "topics": topics]
    }

    @Test func aTreeOfTopicsReachesTheAppWithTheClientsName() async throws {
        let plan = try await storePlan()
        let before = try await harness.repository.loadGraph(for: plan.mapID)

        let result = try await harness.call("propose_topics", arguments(plan, under: "Thiết kế", [
            ["title": "Bảng màu", "note": "  Màu chính và phụ\n", "subtopics": [["title": "Chế độ tối"]]],
            ["title": "Biểu tượng\nứng dụng"],
        ]))

        #expect(!result.isError)
        #expect(result.text.contains("Proposed 3 topics under “Thiết kế” in “Kế hoạch dự án”"))
        #expect(result.text.contains("nothing is added until they accept"))
        #expect(result.structured?["status"] == "waiting_for_review")
        let proposal = try #require(await receiver.received.first)
        #expect(proposal.client == MCPHarness.client)
        #expect(proposal.mapID == plan.mapID)
        #expect(proposal.parentID == plan.ids["Thiết kế"])
        #expect(proposal.topics == [
            .init(id: "p1", parentID: nil, title: "Bảng màu", note: "Màu chính và phụ"),
            .init(id: "p2", parentID: "p1", title: "Chế độ tối", note: nil),
            .init(id: "p3", parentID: nil, title: "Biểu tượng ứng dụng", note: nil),
        ])
        // The server itself writes nothing.
        #expect(try await harness.repository.loadGraph(for: plan.mapID) == before)
    }

    @Test func theAppsAnswerBecomesWhatTheModelReads() async throws {
        let plan = try await storePlan()
        let topics: JSONValue = [["title": "Ý tưởng"]]

        await receiver.answer(.waiting)
        let waiting = try await harness.call("propose_topics", arguments(plan, under: "Thiết kế", topics))
        #expect(!waiting.isError)
        #expect(waiting.text.contains("when the person opens the map"))

        await receiver.answer(.notAllowed)
        let refused = try await harness.call("propose_topics", arguments(plan, under: "Thiết kế", topics))
        #expect(refused.isError)
        #expect(refused.text.contains("Allow Suggestions"))

        await receiver.answer(.tooManyWaiting)
        let full = try await harness.call("propose_topics", arguments(plan, under: "Thiết kế", topics))
        #expect(full.isError)
        #expect(full.text.contains("already has \(MCPProposal.maximumWaiting) proposals waiting"))
    }

    @Test func badProposalsAreToolErrorsAndNeverReachTheApp() async throws {
        let plan = try await storePlan()
        let tooMany = JSONValue.array((1...MapTools.maximumProposedTopics).map { ["title": .string("Chủ đề \($0)")] }
            + [["title": "Một nữa", "subtopics": [["title": "Con"]]]])
        let cases: [(JSONValue?, String)] = [
            (nil, "topics is required"),
            ([], "at least one topic"),
            ("Bảng màu", "topics must be an array"),
            (["Bảng màu"], "topics[0] must be an object"),
            ([["title": "  "]], "topics[0].title is empty"),
            ([["title": .string(String(repeating: "a", count: 201))]], "over 200 characters"),
            ([["title": "A", "note": 3]], "topics[0].note must be a string"),
            ([["title": "A", "subtopics": [["name": "B"]]]], "topics[0].subtopics[0] has an unknown field name"),
            (tooMany, "at most \(MapTools.maximumProposedTopics) topics"),
        ]
        for (topics, message) in cases {
            var args = arguments(plan, under: "Thiết kế", .null)
            args["topics"] = topics
            let result = try await harness.call("propose_topics", args)
            #expect(result.isError, "\(message)")
            #expect(result.text.contains(message), "\(result.text)")
        }

        let noParent = try await harness.call("propose_topics", ["map_id": .string(plan.mapID.description), "topics": [["title": "A"]]])
        #expect(noParent.text.contains("parent_topic_id is required"))
        var unknownTopic = arguments(plan, under: "Thiết kế", [["title": "A"]])
        unknownTopic["parent_topic_id"] = .string(UUID().uuidString)
        #expect(try await harness.call("propose_topics", unknownTopic).text == MapTools.topicNotFound)
        var unknownMap = arguments(plan, under: "Thiết kế", [["title": "A"]])
        unknownMap["map_id"] = .string(UUID().uuidString)
        #expect(try await harness.call("propose_topics", unknownMap).text == MapTools.mapNotFound)

        #expect(await receiver.received.isEmpty)
    }

    @Test func deletedMapsTakeNoProposals() async throws {
        let plan = try await storePlan()
        try await harness.repository.moveToRecentlyDeleted(plan.mapID, at: .now)
        let result = try await harness.call("propose_topics", arguments(plan, under: "Thiết kế", [["title": "A"]]))
        #expect(result.text == MapTools.mapNotFound)
        #expect(await receiver.received.isEmpty)
    }

    @Test func listedLastAsAWriteThatNeverDestroys() async throws {
        let response = await harness.server.handle(MCPHarness.modern("tools/list"))
        let tools = try #require(response.json?["result"]?["tools"]?.arrayValue)
        #expect(tools.compactMap { $0["name"]?.stringValue } == ["list_maps", "get_map", "search", "get_topic", "propose_topics"])
        let propose = try #require(tools.last)
        #expect(propose["annotations"]?["readOnlyHint"] == false)
        #expect(propose["annotations"]?["destructiveHint"] == false)
        #expect(propose["annotations"]?["idempotentHint"] == false)
        #expect(propose["inputSchema"]?["required"] == ["map_id", "parent_topic_id", "topics"])
        #expect(propose["inputSchema"]?["$defs"]?["topic"]?["additionalProperties"] == false)

        let discover = await harness.server.handle(MCPHarness.modern("server/discover"))
        #expect(discover.json?["result"]?["instructions"]?.stringValue?.contains("Nothing can be edited, moved or deleted") == true)
    }

    @Test func aReadOnlyServerHasNoProposeTool() async throws {
        let readOnly = try MCPHarness()
        let response = await readOnly.server.handle(MCPHarness.modern("tools/call", params: ["name": "propose_topics", "arguments": [:]]))
        #expect(response.json?["error"]?["code"] == .int(MCPErrorCode.invalidParams.rawValue))
    }
}

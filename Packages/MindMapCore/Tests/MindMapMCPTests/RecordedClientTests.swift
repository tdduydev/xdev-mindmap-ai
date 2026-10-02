import Foundation
@testable import MindMapMCP
import Testing

/// Replays requests recorded from real clients against the real server, so a
/// change that breaks one of them fails here rather than in someone's app.
@Suite("Recorded clients")
struct RecordedClientTests {
    let harness: MCPHarness

    init() async throws {
        harness = try MCPHarness()
        try await harness.store("Trip to Hanoi", [.topic("Flights"), .topic("Design museum")])
    }

    @Test(arguments: [
        "claude-code-2.1.283-2026-07-28",
        "claude-code-2.1.283-2025-11-25",
        "mcp-inspector-cli-2.9.0-2025-11-25",
    ])
    func everyRecordedRequestIsServed(_ fixture: String) async throws {
        var sawToolCall = false
        for recorded in try MCPHarness.fixture(fixture) {
            let response = await harness.server.handle(recorded.request)
            guard let message = recorded.json else {
                // The legacy GET for a server stream: we offer none.
                #expect(recorded.request.method == "GET")
                #expect(response.status == 405)
                continue
            }
            let method = try #require(message["method"]?.stringValue)
            if message["id"] == nil {
                #expect(response.status == 202, "\(method)")
                #expect(response.body.isEmpty)
                continue
            }
            #expect(response.status == 200, "\(method): \(String(decoding: response.body, as: UTF8.self))")
            let reply = try #require(response.json)
            #expect(reply["id"] == message["id"], "the ID comes back as sent, string or number")
            let result = try #require(reply["result"], "\(method)")

            let isModern = message["params"]?["_meta"]?["io.modelcontextprotocol/protocolVersion"] != nil
            #expect((result["resultType"] == "complete") == isModern, "resultType only in 2026-07-28 results")

            switch method {
            case "server/discover":
                #expect(result["supportedVersions"] == ["2026-07-28", "2025-11-25", "2025-06-18"])
                #expect(result["capabilities"]?["tools"] != nil)
            case "initialize":
                #expect(result["protocolVersion"] == "2025-11-25")
                #expect(result["serverInfo"]?["name"] == "mindmap-ai")
            case "tools/list":
                let names = result["tools"]?.arrayValue?.compactMap { $0["name"]?.stringValue }
                #expect(names == ["list_maps", "get_map", "search", "get_topic"])
                if isModern {
                    #expect(result["ttlMs"]?.intValue != nil)
                    #expect(result["cacheScope"] == "private")
                }
            case "tools/call":
                sawToolCall = true
                #expect(result["isError"] == false)
                let text = try #require(result["content"]?.arrayFirst?["text"]?.stringValue)
                #expect(text.contains("Trip to Hanoi"))
                #expect(result["structuredContent"]?["maps"]?.arrayValue?.count == 1)
            default:
                Issue.record("Unexpected recorded method \(method)")
            }
        }
        #expect(sawToolCall)
    }

    @Test func recordedClientsSendNoOrigin() throws {
        // The Origin rule refuses every request that has one; it holds only
        // while real clients keep not sending it.
        for fixture in ["claude-code-2.1.283-2026-07-28", "claude-code-2.1.283-2025-11-25", "mcp-inspector-cli-2.9.0-2025-11-25"] {
            for recorded in try MCPHarness.fixture(fixture) {
                #expect(recorded.request.header("Origin") == nil, "\(fixture)")
                #expect(MCPServer.isLoopbackHost(recorded.request.header("Host")), "\(fixture)")
            }
        }
    }
}

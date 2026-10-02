import Foundation
@testable import MindMapMCP
import Synchronization
import Testing

@Suite("MCP security and limits")
struct MCPSecurityTests {
    let harness: MCPHarness

    init() throws {
        harness = try MCPHarness()
    }

    func status(_ request: HTTPRequest) async -> Int {
        await harness.server.handle(request).status
    }

    @Test func anyOriginIsRefused() async {
        for origin in ["http://evil.example", "http://127.0.0.1:51947", "null"] {
            let response = await harness.server.handle(MCPHarness.modern("tools/list", headers: ["Origin": origin]))
            #expect(response.status == 403, "\(origin)")
            #expect(response.json?["error"] != nil)
            #expect(response.json?["id"] == nil, "403 carries a JSON-RPC error without an id")
        }
    }

    @Test func aRebindingHostIsRefused() async {
        #expect(await status(MCPHarness.modern("tools/list", headers: ["Host": "attacker.example:51947"])) == 403)
        #expect(await status(MCPHarness.modern("tools/list", headers: ["Host": nil])) == 403)
        for host in ["127.0.0.1:51947", "localhost:51947", "[::1]:51947", "LOCALHOST"] {
            #expect(await status(MCPHarness.modern("tools/list", headers: ["Host": host])) == 200, "\(host)")
        }
    }

    @Test func aMissingWrongOrRevokedTokenIsRefused() async {
        #expect(await status(MCPHarness.modern("tools/list", headers: ["Authorization": nil])) == 401)
        #expect(await status(MCPHarness.modern("tools/list", headers: ["Authorization": "Bearer nope"])) == 401)
        #expect(await status(MCPHarness.modern("tools/list", headers: ["Authorization": "Basic \(MCPHarness.token)"])) == 401)
        #expect(await status(MCPHarness.modern("tools/list", headers: ["Authorization": "Bearer "])) == 401)
        let response = await harness.server.handle(MCPHarness.modern("tools/list", headers: ["Authorization": nil]))
        #expect(response.headers["WWW-Authenticate"] == "Bearer")

        #expect(await status(MCPHarness.modern("tools/list", headers: ["Authorization": "bearer \(MCPHarness.token)"])) == 200)
        harness.access.revoke(MCPHarness.client.id)
        #expect(await status(MCPHarness.modern("tools/list")) == 401)
    }

    @Test func tokenComparisonNeedsTheWholeToken() async {
        let list = MCPTokenList(["abcdef": MCPClient(name: "A")])
        #expect(await list.client(forToken: "abcdef")?.name == "A")
        #expect(await list.client(forToken: "abcde") == nil)
        #expect(await list.client(forToken: "abcdeg") == nil)
        #expect(await list.client(forToken: "abcdefg") == nil)
    }

    @Test func newTokensAreLongAndHeaderSafe() {
        let tokens = (0..<20).map { _ in MCPTokenList.makeToken() }
        #expect(Set(tokens).count == tokens.count)
        for token in tokens {
            #expect(token.count == 43)
            #expect(token.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        }
    }

    @Test func onlyPostOnTheEndpointIsServed() async {
        var get = MCPHarness.modern("tools/list")
        get.method = "GET"
        let response = await harness.server.handle(get)
        #expect(response.status == 405)
        #expect(response.headers["Allow"] == "POST")
        get.method = "DELETE"
        #expect(await status(get) == 405)

        var elsewhere = MCPHarness.modern("tools/list")
        elsewhere.path = "/"
        #expect(await status(elsewhere) == 404)
    }

    @Test func callsPerMinuteAreCappedPerClient() async throws {
        let harness = try MCPHarness { $0.callsPerMinute = 3 }
        let other = MCPClient(name: "Other")
        harness.access.add(other, token: "other-token")

        for _ in 0..<3 {
            #expect(await harness.server.handle(MCPHarness.modern("tools/list")).status == 200)
        }
        let refused = await harness.server.handle(MCPHarness.modern("tools/list"))
        #expect(refused.status == 429)
        let retry = try #require(refused.headers["Retry-After"].flatMap(Int.init))
        #expect((1...60).contains(retry))
        // Another client has its own budget.
        #expect(await harness.server.handle(MCPHarness.modern("tools/list", headers: ["Authorization": "Bearer other-token"])).status == 200)
    }

    @Test func theWindowSlides() {
        let limiter = RateLimiter(limit: 2, window: .seconds(60))
        let client = UUID()
        let start = ContinuousClock.now
        #expect(limiter.admit(client, at: start) == nil)
        #expect(limiter.admit(client, at: start + .seconds(10)) == nil)
        #expect(limiter.admit(client, at: start + .seconds(20)) == .seconds(40))
        #expect(limiter.admit(client, at: start + .seconds(61)) == nil, "the first call left the window")
    }

    @Test func onlyJSONBodiesAreRead() async {
        #expect(await status(MCPHarness.modern("tools/list", headers: ["Content-Type": "text/plain"])) == 415)
        #expect(await status(MCPHarness.modern("tools/list", headers: ["Content-Type": "application/json; charset=utf-8"])) == 200)
    }

    @Test func activityNamesTheClientAndToolOnly() async throws {
        let seen = Mutex<[MCPServer.Activity]>([])
        let harness = try MCPHarness(onActivity: { activity in seen.withLock { $0.append(activity) } })
        _ = try await harness.call("search", ["query": "secret plans"])
        let activity = try #require(seen.withLock { $0.first })
        #expect(activity.client == MCPHarness.client)
        #expect(activity.toolName == "search")
        // tools/list is not a read of maps.
        _ = await harness.server.handle(MCPHarness.modern("tools/list"))
        #expect(seen.withLock { $0.count } == 1)
    }
}

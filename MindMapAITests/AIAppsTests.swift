import Foundation
@testable import MindMapAI
import MindMapAICore
import MindMapDomain
import MindMapGraph
import MindMapMCP
import MindMapPersistence
import MindMapQuery
import MindMapTestSupport
import Testing

/// Settings ▸ AI Apps (MM-46, docs/mcp.md M2): defaults, tokens per app,
/// Revoke, the switch and port, and that apps read the editor's live graph.
/// Requests go to `AIAppsHost.server` directly: the app's sandbox has no
/// network.client, so a socket round trip lives in the core tests (MM-40).
@Suite("AI Apps")
@MainActor
struct AIAppsTests {
    let defaults: UserDefaults
    let repository: SwiftDataMapRepository
    let openMaps: OpenMaps
    let store = InMemoryAIAppClientStore()
    let mapID: MapID

    init() async throws {
        defaults = try #require(UserDefaults(suiteName: "AIAppsTests.\(UUID().uuidString)"))
        repository = try PersistenceController.makeRepository(at: .inMemory)
        openMaps = OpenMaps(repository: repository, clipboard: MemoryClipboard())
        let graph = GraphState.newMap(title: "Kế hoạch")
        try await repository.create(graph)
        mapID = graph.map.id
    }

    private func makeHost(store: (any AIAppClientStore)? = nil) -> AIAppsHost {
        let graphs = OpenMapsGraphSource(openMaps: openMaps, repository: repository)
        return AIAppsHost(
            queries: MapQueries(repository: repository, graphs: graphs),
            store: store ?? self.store,
            defaults: defaults,
            serverVersion: "test"
        )
    }

    /// A 2025-11-25 `tools/call`, as Claude Code sends after `initialize`.
    private func call(_ tool: String, _ arguments: [String: Any] = [:], token: String?, on host: AIAppsHost) async throws -> (status: Int, text: String) {
        let body = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": ["name": tool, "arguments": arguments],
        ])
        var headers: [(name: String, value: String)] = [
            ("Host", "127.0.0.1:\(host.port)"),
            ("Content-Type", "application/json"),
            ("Accept", "application/json, text/event-stream"),
            ("MCP-Protocol-Version", "2025-11-25"),
        ]
        if let token { headers.append(("Authorization", "Bearer \(token)")) }
        let response = await host.server.handle(HTTPRequest(method: "POST", path: "/mcp", headers: headers, body: body))
        return (response.status, String(decoding: response.body, as: UTF8.self))
    }

    /// A port nobody else in this run uses; the listener binds it for real.
    private func freePort() -> UInt16 { UInt16.random(in: 52_000...60_000) }

    // MARK: Defaults

    @Test func offByDefaultOnTheDocumentedPort() {
        let host = makeHost()
        host.start()
        #expect(!host.isEnabled)
        #expect(host.status == .off)
        #expect(host.port == 51947)
        #expect(host.apps.isEmpty)
    }

    @Test func storedPortOutOfRangeGivesTheDefault() {
        defaults.set(80, forKey: AIAppsHost.portKey)
        #expect(AIAppsHost.storedPort(in: defaults) == 51947)
        defaults.set(70_000, forKey: AIAppsHost.portKey)
        #expect(AIAppsHost.storedPort(in: defaults) == 51947)
        defaults.set(52_100, forKey: AIAppsHost.portKey)
        #expect(AIAppsHost.storedPort(in: defaults) == 52_100)
    }

    @Test func invalidPortIsRefusedAndNotStored() {
        let host = makeHost()
        #expect(!host.setPort(80))
        #expect(host.port == 51947)
        #expect(defaults.object(forKey: AIAppsHost.portKey) == nil)
        #expect(host.setPort(52_200))
        #expect(defaults.integer(forKey: AIAppsHost.portKey) == 52_200)
    }

    // MARK: Apps and tokens

    @Test func addedAppReadsWithItsTokenAndNothingElseDoes() async throws {
        let host = makeHost()
        host.start()
        let token = try host.addApp(named: "  Claude Code ")

        #expect(host.apps.map(\.name) == ["Claude Code"])
        #expect(try store.load().map(\.token) == [token])
        #expect(token.count == 43)

        let read = try await call("list_maps", token: token, on: host)
        #expect(read.status == 200)
        #expect(read.text.contains("Kế hoạch"))
        #expect(try await call("list_maps", token: nil, on: host).status == 401)
        #expect(try await call("list_maps", token: MCPTokenList.makeToken(), on: host).status == 401)
    }

    @Test func eachAppHasItsOwnToken() throws {
        let host = makeHost()
        let first = try host.addApp(named: "Claude Code")
        let second = try host.addApp(named: "Cursor")
        #expect(first != second)
        #expect(host.apps.map(\.name) == ["Claude Code", "Cursor"])
    }

    @Test func revokeStopsTheTokenAndForgetsTheApp() async throws {
        let host = makeHost()
        let kept = try host.addApp(named: "Cursor")
        let token = try host.addApp(named: "Claude Code")
        let claude = try #require(host.apps.last)

        try host.revoke(claude.id)

        #expect(host.apps.map(\.name) == ["Cursor"])
        #expect(try store.load().map(\.client.name) == ["Cursor"])
        #expect(try await call("list_maps", token: token, on: host).status == 401)
        #expect(try await call("list_maps", token: kept, on: host).status == 200)
    }

    @Test func appsComeBackAtLaunchWithoutTheirLastRead() async throws {
        let first = makeHost()
        let token = try first.addApp(named: "VS Code")

        let relaunched = makeHost()
        relaunched.start()

        #expect(relaunched.apps.map(\.name) == ["VS Code"])
        #expect(relaunched.apps.first?.lastRead == nil)
        #expect(try await call("list_maps", token: token, on: relaunched).status == 200)
    }

    @Test func aToolCallSetsLastRead() async throws {
        let host = makeHost()
        let token = try host.addApp(named: "ChatGPT")
        let before = Date.now

        _ = try await call("list_maps", token: token, on: host)
        // The server reports activity from its own task; give it a turn on the main actor.
        for _ in 0..<50 where host.apps.first?.lastRead == nil { await Task.yield() }

        let lastRead = try #require(host.apps.first?.lastRead)
        #expect(lastRead >= before)
    }

    @Test func keychainFailureShowsNoAppsAndReadsNothing() {
        let host = makeHost(store: FailingStore())
        host.start()
        #expect(host.keychainFailed)
        #expect(host.apps.isEmpty)
    }

    // MARK: What apps read

    @Test func appsReadTheOpenMapBeforeItIsSaved() async throws {
        let host = makeHost()
        let token = try host.addApp(named: "Claude Code")
        guard case .ready(let open) = await openMaps.open(mapID, in: WindowToken(), service: AIService(provider: { MockAIProvider() }, entitlements: Unlocked())) else {
            Issue.record("The map did not open")
            return
        }
        open.session.addChild()
        guard let topic = open.session.selection else {
            Issue.record("No new topic selected")
            return
        }
        open.session.rename(topic, to: "Thiết kế giao diện")

        let read = try await call("get_map", ["map_id": mapID.rawValue.uuidString], token: token, on: host)

        #expect(read.text.contains("Thiết kế giao diện"))
    }

    // MARK: Switch and port

    @Test func switchOpensAndClosesThePortAndRevokesNothing() async throws {
        let host = makeHost()
        host.start()
        #expect(host.setPort(freePort()))
        _ = try host.addApp(named: "Claude Code")

        host.setEnabled(true)
        #expect(defaults.bool(forKey: AIAppsHost.enabledKey))
        try await waitFor(host) { if case .listening = $0 { true } else { false } }
        #expect(host.status == .listening(port: host.port))

        host.setEnabled(false)
        #expect(host.status == .off)
        #expect(!defaults.bool(forKey: AIAppsHost.enabledKey))
        #expect(host.apps.map(\.name) == ["Claude Code"])
    }

    @Test func switchOnAtLaunchListens() async throws {
        defaults.set(true, forKey: AIAppsHost.enabledKey)
        defaults.set(Int(freePort()), forKey: AIAppsHost.portKey)
        let host = makeHost()
        host.start()
        try await waitFor(host) { if case .listening = $0 { true } else { false } }
        host.setEnabled(false)
    }

    @Test func aTakenPortIsReportedNotReplaced() async throws {
        let port = freePort()
        let first = makeHost()
        first.setPort(port)
        first.setEnabled(true)
        try await waitFor(first) { if case .listening = $0 { true } else { false } }

        let otherDefaults = try #require(UserDefaults(suiteName: "AIAppsTests.\(UUID().uuidString)"))
        let second = AIAppsHost(
            queries: MapQueries(repository: repository, graphs: RepositoryGraphSource(repository: repository)),
            store: InMemoryAIAppClientStore(),
            defaults: otherDefaults,
            serverVersion: "test"
        )
        second.setPort(port)
        second.setEnabled(true)
        try await waitFor(second) { if case .portUnavailable = $0 { true } else { false } }
        #expect(second.status == .portUnavailable(port: port))
        #expect(second.port == port)

        first.setEnabled(false)
        second.setEnabled(false)
    }

    private struct TimedOut: Error {}

    private func waitFor(_ host: AIAppsHost, _ condition: (AIAppsHost.Status) -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition(host.status) {
            guard ContinuousClock.now < deadline else { throw TimedOut() }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    // MARK: Keychain

    @Test func keychainKeepsTokensPerApp() throws {
        let keychain = KeychainAIAppClientStore(service: "asia.xdev.mindmapai.tests.\(UUID().uuidString)")
        let claude = StoredAIApp(client: MCPClient(name: "Claude Code"), token: MCPTokenList.makeToken(), addedAt: .now)
        let cursor = StoredAIApp(client: MCPClient(name: "Cursor"), token: MCPTokenList.makeToken(), addedAt: .now)
        defer {
            try? keychain.delete(claude.client.id)
            try? keychain.delete(cursor.client.id)
        }

        try keychain.save(claude)
        try keychain.save(cursor)
        let loaded = try keychain.load()
        #expect(Set(loaded.map(\.client)) == [claude.client, cursor.client])
        #expect(Set(loaded.map(\.token)) == [claude.token, cursor.token])

        try keychain.delete(claude.client.id)
        #expect(try keychain.load().map(\.client) == [cursor.client])
        // Deleting what is gone is not an error: Revoke may run twice.
        try keychain.delete(claude.client.id)
    }

    // MARK: Setup snippets

    @Test func snippetsCarryTheAddressAndToken() throws {
        let token = MCPTokenList.makeToken()
        for kind in AIAppKind.allCases {
            let snippet = AIAppSetup.snippet(for: kind, port: 52_300, token: token)
            #expect(snippet.contains("http://127.0.0.1:52300/mcp"), "\(kind)")
            #expect(snippet.contains("Bearer \(token)"), "\(kind)")
        }
    }

    @Test func jsonSnippetsAreTheShapeEachAppReads() throws {
        let token = MCPTokenList.makeToken()
        let cursor = try #require(try JSONSerialization.jsonObject(with: Data(AIAppSetup.snippet(for: .cursor, port: 51947, token: token).utf8)) as? [String: Any])
        let cursorServer = try #require((cursor["mcpServers"] as? [String: Any])?["mindmap-ai"] as? [String: Any])
        #expect(cursorServer["url"] as? String == "http://127.0.0.1:51947/mcp")
        #expect((cursorServer["headers"] as? [String: String])?["Authorization"] == "Bearer \(token)")

        let vsCode = try #require(try JSONSerialization.jsonObject(with: Data(AIAppSetup.snippet(for: .vsCode, port: 51947, token: token).utf8)) as? [String: Any])
        let vsCodeServer = try #require((vsCode["servers"] as? [String: Any])?["mindmap-ai"] as? [String: Any])
        #expect(vsCodeServer["type"] as? String == "http")
        #expect((vsCodeServer["headers"] as? [String: String])?["Authorization"] == "Bearer \(token)")
    }

    @Test func claudeCodeAndChatGPTSnippets() {
        #expect(AIAppSetup.snippet(for: .claudeCode, port: 51947, token: "T")
            == "claude mcp add --transport http --scope user mindmap-ai http://127.0.0.1:51947/mcp --header \"Authorization: Bearer T\"")
        #expect(AIAppSetup.snippet(for: .chatGPT, port: 51947, token: "T") == """
            [mcp_servers.mindmap-ai]
            url = "http://127.0.0.1:51947/mcp"
            http_headers = { "Authorization" = "Bearer T" }
            """)
    }
}

private struct Unlocked: ProEntitlements {
    func allows(_ feature: ProFeature) -> Bool { true }
}

private final class FailingStore: AIAppClientStore {
    struct Refused: Error {}
    func load() throws -> [StoredAIApp] { throw Refused() }
    func save(_ app: StoredAIApp) throws { throw Refused() }
    func delete(_ id: MCPClient.ID) throws { throw Refused() }
}

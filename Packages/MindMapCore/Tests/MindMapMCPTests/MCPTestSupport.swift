import Foundation
import MindMapDomain
import MindMapGraph
@testable import MindMapMCP
import MindMapPersistence
import MindMapQuery
import Testing

/// A server over an in-memory store, with the token the recorded fixtures carry.
struct MCPHarness {
    static let token = "test-token-0123"
    static let client = MCPClient(name: "Recorded client")

    let repository: SwiftDataMapRepository
    let access: MCPTokenList
    let server: MCPServer

    init(configure: (inout MCPServer.Configuration) -> Void = { _ in },
         proposals: (any MCPProposalReceiver)? = nil,
         onActivity: @escaping @Sendable (MCPServer.Activity) -> Void = { _ in }) throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
        access = MCPTokenList([Self.token: Self.client])
        var configuration = MCPServer.Configuration(serverVersion: "test")
        configure(&configuration)
        server = MCPServer(
            queries: MapQueries(repository: repository, graphs: RepositoryGraphSource(repository: repository)),
            access: access,
            configuration: configuration,
            proposals: proposals,
            onActivity: onActivity
        )
    }

    // MARK: Maps

    struct Built {
        var state: GraphState
        var ids: [String: NodeID]
        var mapID: MapID { state.map.id }
    }

    indirect enum Row {
        case topic(String, note: String? = nil, [Row] = [])
    }

    @discardableResult
    func store(
        _ title: String, edited: Date = .now, _ rows: [Row] = [],
        // Task fields and cross-links, once every topic has its ID.
        extras: (inout [MindNode], [String: NodeID], MapID) -> [MindEdge] = { _, _, _ in [] }
    ) async throws -> Built {
        let mapID = MapID()
        let rootID = NodeID()
        var nodes = [MindNode(id: rootID, mapID: mapID, parentID: nil, title: title, createdAt: edited)]
        var ids = [title: rootID]
        func add(_ rows: [Row], under parentID: NodeID) {
            for (index, row) in rows.enumerated() {
                guard case let .topic(text, note, children) = row else { continue }
                let id = NodeID()
                nodes.append(MindNode(id: id, mapID: mapID, parentID: parentID, title: text, note: note,
                                      sortOrder: Double(index), createdAt: edited))
                ids[text] = id
                add(children, under: id)
            }
        }
        add(rows, under: rootID)
        let edges = extras(&nodes, ids, mapID)
        let map = MindMap(id: mapID, title: title, rootNodeID: rootID, createdAt: edited)
        let built = Built(state: GraphState(map: map, nodes: nodes, edges: edges), ids: ids)
        try await repository.create(built.state)
        return built
    }

    // MARK: Requests

    static let modernMeta: JSONValue = [
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientInfo": ["name": "tests", "version": "1"],
        "io.modelcontextprotocol/clientCapabilities": [:],
    ]

    /// A 2026-07-28 request with the headers a conforming client sends.
    static func modern(_ method: String, id: JSONValue = 1, params: [String: JSONValue] = [:],
                       headers: [String: String?] = [:]) -> HTTPRequest {
        var params = params
        params["_meta"] = modernMeta
        var all: [String: String?] = [
            "Host": "127.0.0.1:51947",
            "Authorization": "Bearer \(token)",
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
            "MCP-Protocol-Version": "2026-07-28",
            "Mcp-Method": method,
        ]
        if method == "tools/call", let name = params["name"]?.stringValue { all["Mcp-Name"] = name }
        all.merge(headers) { $1 }
        let body: JSONValue = ["jsonrpc": "2.0", "id": id, "method": .string(method), "params": .object(params)]
        return HTTPRequest(method: "POST", path: "/mcp",
                           headers: all.compactMap { key, value in value.map { (key, $0) } }, body: body.encoded())
    }

    /// A 2025-11-25 request after `initialize`.
    static func legacy(_ method: String, id: JSONValue? = 1, params: [String: JSONValue]? = nil,
                       headers: [String: String?] = [:]) -> HTTPRequest {
        var all: [String: String?] = [
            "Host": "127.0.0.1:51947",
            "Authorization": "Bearer \(token)",
            "Content-Type": "application/json",
            "MCP-Protocol-Version": "2025-11-25",
        ]
        all.merge(headers) { $1 }
        var body: [String: JSONValue] = ["jsonrpc": "2.0", "method": .string(method)]
        if let id { body["id"] = id }
        if let params { body["params"] = .object(params) }
        return HTTPRequest(method: "POST", path: "/mcp",
                           headers: all.compactMap { key, value in value.map { (key, $0) } },
                           body: JSONValue.object(body).encoded())
    }

    func call(_ tool: String, _ arguments: [String: JSONValue] = [:]) async throws -> (text: String, structured: JSONValue?, isError: Bool) {
        let response = await server.handle(Self.modern("tools/call", params: ["name": .string(tool), "arguments": .object(arguments)]))
        let result = try #require(try JSONValue.decode(response.body)["result"])
        let text = result["content"]?.arrayFirst?["text"]?.stringValue ?? ""
        return (text, result["structuredContent"], result["isError"]?.boolValue ?? false)
    }

    // MARK: Fixtures

    struct Recorded {
        var request: HTTPRequest
        var json: JSONValue?
    }

    /// Requests recorded from a real client (see Fixtures/README.md).
    static func fixture(_ name: String) throws -> [Recorded] {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "jsonl"))
        return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map { line in
            let entry = try JSONValue.decode(Data(line.utf8))
            let headers: [(name: String, value: String)] = (entry["headers"].flatMap {
                guard case let .array(pairs) = $0 else { return nil }
                return pairs.compactMap { pair -> (String, String)? in
                    guard case let .array(parts) = pair, parts.count == 2,
                          let name = parts[0].stringValue, let value = parts[1].stringValue else { return nil }
                    return (name, value)
                }
            }) ?? []
            let body = entry["body"]?.stringValue
            return Recorded(
                request: HTTPRequest(method: entry["method"]?.stringValue ?? "", path: entry["path"]?.stringValue ?? "",
                                     headers: headers, body: Data((body ?? "").utf8)),
                json: body.flatMap { try? JSONValue.decode(Data($0.utf8)) }
            )
        }
    }
}

extension JSONValue {
    var arrayValue: [JSONValue]? {
        guard case let .array(items) = self else { return nil }
        return items
    }

    var arrayFirst: JSONValue? { arrayValue?.first }
}

extension HTTPResponse {
    var json: JSONValue? { try? JSONValue.decode(body) }
}

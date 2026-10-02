// Serves two sample maps from an in-memory store so the MCP Inspector or a
// real client can talk to MindMapMCP before the app hosts it (M2). Not shipped.
//
//   swift run --package-path Packages/MindMapCore mindmap-mcp-dev [port]
//
// The token comes from MINDMAP_MCP_TOKEN, or a new one is printed.
import Foundation
import MindMapDomain
import MindMapGraph
import MindMapMCP
import MindMapPersistence
import MindMapQuery

// Line-buffered, so the URL shows up when stdout is a file or a pipe.
setvbuf(stdout, nil, _IOLBF, 0)

let port = CommandLine.arguments.dropFirst().first.flatMap(UInt16.init) ?? MCPListener.defaultPort
let token = ProcessInfo.processInfo.environment["MINDMAP_MCP_TOKEN"] ?? MCPTokenList.makeToken()

func sampleMap(_ title: String, _ rows: [(String, String?, [String])]) -> GraphState {
    let map = MindMap(title: title)
    var root = MindNode(mapID: map.id, parentID: nil, title: title)
    root.note = "Sample map served by mindmap-mcp-dev."
    var nodes = [root]
    var edges: [MindEdge] = []
    for (index, row) in rows.enumerated() {
        let topic = MindNode(mapID: map.id, parentID: root.id, title: row.0, note: row.1, sortOrder: Double(index))
        nodes.append(topic)
        for (childIndex, child) in row.2.enumerated() {
            nodes.append(MindNode(mapID: map.id, parentID: topic.id, title: child, sortOrder: Double(childIndex)))
        }
    }
    if nodes.count > 3 {
        edges.append(MindEdge(mapID: map.id, sourceNodeID: nodes[1].id, targetNodeID: nodes[nodes.count - 1].id, label: "depends on"))
    }
    var withRoot = map
    withRoot.rootNodeID = root.id
    return GraphState(map: withRoot, nodes: nodes, edges: edges)
}

let repository = try PersistenceController.makeRepository(at: .inMemory)
try await repository.create(sampleMap("Trip to Hanoi", [
    ("Flights", "Book the design conference first", ["Outbound", "Return"]),
    ("Design museum", nil, []),
    ("Street food", "Phở, bún chả, bánh mì", ["Old Quarter"]),
]))
try await repository.create(sampleMap("Kế hoạch dự án", [
    ("Thiết kế", "Phác thảo giao diện đầu tiên", ["Màn hình đăng nhập", "Đặt lịch"]),
    ("Ngân sách", "Chi phí đi lại và thiết kế bao bì", []),
]))

let queries = MapQueries(repository: repository, graphs: RepositoryGraphSource(repository: repository))
let access = MCPTokenList([token: MCPClient(name: "Developer")])
let server = MCPServer(queries: queries, access: access, configuration: .init(serverVersion: "dev"))
let listener = try MCPListener(server: server, port: port)
listener.start()

for await state in listener.states {
    switch state {
    case let .ready(port):
        print("""
            MindMap AI MCP dev server on http://127.0.0.1:\(port)/mcp
            Authorization: Bearer \(token)
            claude mcp add --transport http mindmap-dev http://127.0.0.1:\(port)/mcp --header "Authorization: Bearer \(token)"
            """)
    case let .failed(reason):
        print("Could not listen on port \(port): \(reason)")
        exit(1)
    case .stopped:
        exit(0)
    case .starting:
        break
    }
}

import Darwin
import Foundation
import Security

// Stands in for the app: listens on a Unix socket in the App Group container
// and answers MCP 2025-11-25 with one tool. No network entitlement on purpose.
@main
enum SpikeServer {
    static func main() {
        guard let container = SpikeSocket.groupContainer() else { SpikeSocket.log("no group container"); exit(2) }
        try? FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let path = container.appendingPathComponent("mcp.sock").path
        SpikeSocket.log("sandboxed=\(ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil) path=\(path) len=\(path.utf8.count)")
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0, var addr = SpikeSocket.address(path) else { SpikeSocket.log("socket: \(SpikeSocket.errno_())"); exit(3) }
        let bound = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard bound == 0 else { SpikeSocket.log("bind: \(SpikeSocket.errno_())"); exit(4) }
        chmod(path, 0o600)
        guard listen(fd, 8) == 0 else { SpikeSocket.log("listen: \(SpikeSocket.errno_())"); exit(5) }
        SpikeSocket.log("listening")
        while true {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { continue }
            // The kernel names the peer; the app can check its code signature
            // before answering instead of asking for a token.
            let verdict = peerIsHelper(client)
            SpikeSocket.log("accepted peer: \(verdict.detail)")
            guard verdict.allowed else { close(client); continue }
            Thread.detachNewThread { serve(client) }
        }
    }

    /// Audit token, not PID, so a reused PID cannot pass as the helper.
    static func peerIsHelper(_ fd: Int32) -> (allowed: Bool, detail: String) {
        var token = audit_token_t()
        var len = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &len) == 0 else { return (false, "no audit token") }
        let tokenData = withUnsafeBytes(of: &token) { Data($0) }
        var code: SecCode?
        let attributes = [kSecGuestAttributeAudit: tokenData] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code else { return (false, "no code object") }
        // Team and identifier only: the App Store re-signs the helper with
        // Apple's certificate but keeps both.
        let identifier = ProcessInfo.processInfo.environment["SPIKE_HELPER_ID"] ?? "asia.xdev.mindmapai.spike2-helper"
        let text = "anchor apple generic and certificate leaf[subject.OU] = \"M6C7NX9MUZ\" and identifier \"\(identifier)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement else { return (false, "bad requirement") }
        let status = SecCodeCheckValidity(code, [], requirement)
        return (status == errSecSuccess, "requirement status \(status)")
    }

    static func serve(_ fd: Int32) {
        var reader = LineReader(fd: fd)
        while let line = reader.next() {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let method = object["method"] as? String else { continue }
            guard let id = object["id"] else { continue } // notification
            let result: Any
            switch method {
            case "initialize":
                result = ["protocolVersion": "2025-11-25", "capabilities": ["tools": [:]],
                          "serverInfo": ["name": "mindmap-spike", "version": "0"]]
            case "tools/list":
                result = ["tools": [["name": "list_maps", "description": "Lists the maps.",
                                     "inputSchema": ["type": "object", "properties": [:]]]]]
            case "tools/call":
                result = ["content": [["type": "text", "text": "Spike map: Launch plan (served over the App Group socket)"]], "isError": false]
            case "ping":
                result = [:]
            default:
                let error = ["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found"]] as [String: Any]
                _ = writeAll(fd, String(decoding: try! JSONSerialization.data(withJSONObject: error), as: UTF8.self))
                continue
            }
            let reply = ["jsonrpc": "2.0", "id": id, "result": result] as [String: Any]
            _ = writeAll(fd, String(decoding: try! JSONSerialization.data(withJSONObject: reply), as: UTF8.self))
        }
        close(fd)
    }
}

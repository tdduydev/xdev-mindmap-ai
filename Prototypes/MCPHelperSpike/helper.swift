import Darwin
import Foundation

// The mindmap-mcp helper: the AI app launches it, it copies newline-delimited
// JSON-RPC between stdio and the app's socket and nothing else.
@main
enum MindMapMCPHelper {
    static func main() {
        signal(SIGPIPE, SIG_IGN)
        SpikeSocket.log("helper sandboxed=\(ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil) parent=\(getppid())")
        guard let container = SpikeSocket.groupContainer() else { fail("no group container") }
        let path = container.appendingPathComponent("mcp.sock").path
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0, var addr = SpikeSocket.address(path) else { fail("socket: \(SpikeSocket.errno_())") }
        let connected = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard connected == 0 else { fail("connect \(path): \(SpikeSocket.errno_())") }
        SpikeSocket.log("helper connected")
        Thread.detachNewThread {
            var fromApp = LineReader(fd: fd)
            while let line = fromApp.next() { if !writeAll(STDOUT_FILENO, line) { break } }
            exit(0)
        }
        var fromClient = LineReader(fd: STDIN_FILENO)
        while let line = fromClient.next() { if !writeAll(fd, line) { break } }
        // The client closed stdin: let the app finish the replies in flight,
        // the reader thread exits when the app closes its end.
        shutdown(fd, SHUT_WR)
        while true { pause() }
    }

    /// The app is not running: answer every request with an error the model can relay.
    static func fail(_ reason: String) -> Never {
        SpikeSocket.log("helper: \(reason)")
        var reader = LineReader(fd: STDIN_FILENO)
        while let line = reader.next() {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let id = object["id"] else { continue }
            let error = ["jsonrpc": "2.0", "id": id,
                         "error": ["code": -32000, "message": "Open MindMap AI to let AI apps read your maps."]] as [String: Any]
            _ = writeAll(STDOUT_FILENO, String(decoding: try! JSONSerialization.data(withJSONObject: error), as: UTF8.self))
        }
        exit(1)
    }
}

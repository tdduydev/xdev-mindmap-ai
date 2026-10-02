import Foundation
import Network
import OSLog
import Synchronization

/// Serves an `MCPServer` over HTTP/1.1 on 127.0.0.1 only (ADR 0008). Started
/// by the Mac app while the switch in Settings is on (M2); iPad and iPhone
/// build it but never start it.
public final class MCPListener: Sendable {
    public enum State: Sendable, Equatable {
        case starting
        /// Listening on this port.
        case ready(port: UInt16)
        /// The port is taken or cannot be opened. Settings says so; the app
        /// does not try another port, since every client config holds the URL.
        case failed(String)
        case stopped
    }

    /// The default port [Đề xuất]: in the dynamic range (49152–65535, which IANA
    /// never assigns) and fixed, since every client's config holds the URL.
    public static let defaultPort: UInt16 = 51947

    /// Connections at once. Each client opens one or two; more means a
    /// runaway loop, which is refused rather than queued.
    static let maximumConnections = 16
    /// A connection that sends nothing for this long is closed.
    static let idleTimeout: Duration = .seconds(30)

    private let server: MCPServer
    private let queue = DispatchQueue(label: "asia.xdev.mindmapai.mcp")
    private let listener: NWListener
    private let connections = Mutex<[ObjectIdentifier: NWConnection]>([:])
    private let stateContinuation: AsyncStream<State>.Continuation
    /// Every state change, starting with `.starting`.
    public let states: AsyncStream<State>

    private static let log = Logger(subsystem: "asia.xdev.mindmapai", category: "MCP")

    /// `port` 0 asks the system for a free port (tests). Throws when the
    /// parameters are refused outright; a taken port arrives as `.failed`.
    public init(server: MCPServer, port: UInt16) throws {
        self.server = server
        let parameters = NWParameters.tcp
        // Both the address and acceptLocalOnly: the first binds loopback, the
        // second refuses anything routed from another interface regardless.
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port) ?? .any)
        parameters.acceptLocalOnly = true
        parameters.allowLocalEndpointReuse = true
        listener = try NWListener(using: parameters)
        (states, stateContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(8))
    }

    public func start() {
        stateContinuation.yield(.starting)
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                let port = listener.port?.rawValue ?? 0
                Self.log.info("Listening on 127.0.0.1:\(port, privacy: .public)")
                stateContinuation.yield(.ready(port: port))
            case let .failed(error):
                Self.log.error("Listener failed: \(error.localizedDescription, privacy: .public)")
                stateContinuation.yield(.failed(error.localizedDescription))
                listener.cancel()
            case .cancelled:
                stateContinuation.yield(.stopped)
                stateContinuation.finish()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
    }

    /// Closes the port and every open connection.
    public func stop() {
        listener.cancel()
        let open = connections.withLock { open in
            defer { open.removeAll() }
            return Array(open.values)
        }
        open.forEach { $0.cancel() }
    }

    // MARK: Connections

    private func accept(_ connection: NWConnection) {
        let admitted = connections.withLock { open in
            guard open.count < Self.maximumConnections else { return false }
            open[ObjectIdentifier(connection)] = connection
            return true
        }
        guard admitted else {
            Self.log.notice("Refused a connection: \(Self.maximumConnections) already open")
            connection.cancel()
            return
        }
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.connections.withLock { _ = $0.removeValue(forKey: ObjectIdentifier(connection)) }
            default:
                break
            }
        }
        connection.start(queue: queue)
        let session = ConnectionSession(
            connection: connection,
            server: server,
            parser: HTTPRequestParser(
                maximumHeaderBytes: server.configuration.maximumHeaderBytes,
                maximumBodyBytes: server.configuration.maximumBodyBytes
            )
        )
        Task { await session.run() }
    }
}

/// One keep-alive connection: read a request, answer it, repeat. Requests on
/// one connection are answered in order, as HTTP/1.1 requires.
private actor ConnectionSession {
    let connection: NWConnection
    let server: MCPServer
    var parser: HTTPRequestParser

    init(connection: NWConnection, server: MCPServer, parser: HTTPRequestParser) {
        self.connection = connection
        self.server = server
        self.parser = parser
    }

    func run() async {
        defer { connection.cancel() }
        while true {
            let request: HTTPRequest
            do throws(HTTPRequestParser.Failure) {
                guard let next = try parser.next() else {
                    guard let data = await receive(), !data.isEmpty else { return }
                    parser.append(data)
                    continue
                }
                request = next
            } catch {
                guard case let .reject(status) = error else { return }
                await send(HTTPResponse(status: status), closing: true)
                return
            }
            let response = await server.handle(request)
            let closing = request.header("Connection")?.lowercased() == "close"
            await send(response, closing: closing)
            if closing { return }
        }
    }

    /// Nil when the peer closed, the connection failed, or it sat idle too long.
    private func receive() async -> Data? {
        await withTaskGroup(of: Data?.self) { group in
            group.addTask { [connection] in
                await withCheckedContinuation { continuation in
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                        if error != nil {
                            continuation.resume(returning: nil)
                        } else if let data, !data.isEmpty {
                            continuation.resume(returning: data)
                        } else {
                            continuation.resume(returning: isComplete ? nil : Data())
                        }
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: MCPListener.idleTimeout)
                return nil
            }
            let first = await group.next() ?? nil
            // On timeout the receive is still pending; cancelling the
            // connection (in run's defer) completes it with an error.
            if first == nil { connection.cancel() }
            group.cancelAll()
            return first
        }
    }

    private func send(_ response: HTTPResponse, closing: Bool) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(content: response.serialized(closing: closing), completion: .contentProcessed { _ in
                continuation.resume()
            })
        }
    }
}

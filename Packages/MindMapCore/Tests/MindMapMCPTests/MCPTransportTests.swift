import Foundation
@testable import MindMapMCP
import Testing

@Suite("MCP transport")
struct MCPTransportTests {
    static func raw(_ body: String, extraHeaders: String = "") -> Data {
        Data("POST /mcp?x=1 HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\n\(extraHeaders)Content-Length: \(body.utf8.count)\r\n\r\n\(body)".utf8)
    }

    func parser() -> HTTPRequestParser {
        HTTPRequestParser(maximumHeaderBytes: 1_024, maximumBodyBytes: 64)
    }

    // MARK: Parsing

    @Test func aRequestSplitAcrossReadsIsAssembled() throws {
        var parser = parser()
        let bytes = Self.raw(#"{"a":"đ"}"#)
        for (index, byte) in bytes.enumerated() {
            #expect(try parser.next() == nil, "incomplete at byte \(index)")
            parser.append(Data([byte]))
        }
        let request = try #require(try parser.next())
        #expect(request.method == "POST")
        #expect(request.path == "/mcp", "the query string is dropped")
        #expect(request.header("content-type") == "application/json")
        #expect(String(decoding: request.body, as: UTF8.self) == #"{"a":"đ"}"#)
        #expect(!parser.hasBufferedBytes)
    }

    @Test func pipelinedRequestsComeOutInOrder() throws {
        var parser = parser()
        parser.append(Self.raw("1") + Self.raw("22"))
        #expect(try parser.next()?.body == Data("1".utf8))
        #expect(try parser.next()?.body == Data("22".utf8))
        #expect(try parser.next() == nil)
    }

    @Test func oversizedRequestsAreRefusedBeforeTheBodyArrives() {
        var parser = parser()
        parser.append(Data("POST /mcp HTTP/1.1\r\nContent-Length: 65\r\n\r\n".utf8))
        #expect(throws: HTTPRequestParser.Failure.reject(413)) { try parser.next() }

        var headers = self.parser()
        headers.append(Data(("POST /mcp HTTP/1.1\r\nX: " + String(repeating: "a", count: 2_000)).utf8))
        #expect(throws: HTTPRequestParser.Failure.reject(431)) { try headers.next() }
    }

    @Test func malformedOrChunkedRequestsAreRefused() {
        for (head, status) in [
            ("GARBAGE\r\n\r\n", 400),
            ("POST /mcp HTTP/1.1\r\nNoColon\r\n\r\n", 400),
            ("POST /mcp HTTP/1.1\r\nContent-Length: -1\r\n\r\n", 400),
            ("POST /mcp HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n", 411),
        ] {
            var parser = parser()
            parser.append(Data(head.utf8))
            #expect(throws: HTTPRequestParser.Failure.reject(status), "\(head)") { try parser.next() }
        }
    }

    @Test func responsesAlwaysCarryALength() {
        let response = HTTPResponse(status: 202)
        let text = String(decoding: response.serialized(closing: false), as: UTF8.self)
        #expect(text.hasPrefix("HTTP/1.1 202 Accepted\r\n"))
        #expect(text.contains("Content-Length: 0\r\n"))
        #expect(text.contains("Connection: keep-alive\r\n"))
        #expect(text.hasSuffix("\r\n\r\n"))
    }

    // MARK: Listener

    @Test func theListenerServesLoopbackOverHTTP() async throws {
        let harness = try MCPHarness()
        try await harness.store("Trip to Hanoi", [.topic("Flights")])
        let listener = try MCPListener(server: harness.server, port: 0)
        listener.start()
        defer { listener.stop() }

        var port: UInt16?
        for await state in listener.states {
            if case let .ready(ready) = state { port = ready; break }
            if case let .failed(reason) = state { Issue.record("listener failed: \(reason)"); return }
        }
        let ready = try #require(port)
        let url = try #require(URL(string: "http://127.0.0.1:\(ready)/mcp"))
        let session = URLSession(configuration: .ephemeral)

        // Two requests, so the second one reuses the kept-alive connection.
        for (id, method) in [(1, "tools/list"), (2, "tools/call")] {
            let template = MCPHarness.modern(method, id: .int(id), params: method == "tools/call" ? ["name": "list_maps"] : [:])
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            for header in template.headers where header.name != "Host" {
                request.setValue(header.value, forHTTPHeaderField: header.name)
            }
            request.httpBody = template.body
            let (data, response) = try await session.data(for: request)
            #expect((response as? HTTPURLResponse)?.statusCode == 200)
            let json = try JSONValue.decode(data)
            #expect(json["id"] == .int(id))
            if method == "tools/call" {
                #expect(json["result"]?["content"]?.arrayFirst?["text"]?.stringValue?.contains("Trip to Hanoi") == true)
            }
        }

        var unauthorized = URLRequest(url: url)
        unauthorized.httpMethod = "POST"
        unauthorized.httpBody = Data("{}".utf8)
        let (_, refused) = try await session.data(for: unauthorized)
        #expect((refused as? HTTPURLResponse)?.statusCode == 401)
    }

    @Test func aTakenPortIsReportedNotReplaced() async throws {
        let harness = try MCPHarness()
        let first = try MCPListener(server: harness.server, port: 0)
        first.start()
        defer { first.stop() }
        var port: UInt16 = 0
        for await state in first.states {
            if case let .ready(ready) = state { port = ready; break }
        }
        let second = try MCPListener(server: harness.server, port: port)
        second.start()
        defer { second.stop() }
        var outcome: MCPListener.State?
        for await state in second.states where state != .starting {
            outcome = state
            break
        }
        guard case .failed = outcome else {
            Issue.record("expected the second listener to fail, got \(String(describing: outcome))")
            return
        }
    }
}

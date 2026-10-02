import Foundation

/// One HTTP/1.1 request, as far as the MCP endpoint needs it.
public struct HTTPRequest: Sendable, Equatable {
    public var method: String
    /// The request target without the query string.
    public var path: String
    /// Names as sent; look them up with `header(_:)`, which ignores case.
    public var headers: [(name: String, value: String)]
    public var body: Data

    public init(method: String, path: String, headers: [(name: String, value: String)] = [], body: Data = Data()) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }

    /// The first value of a header; names are case-insensitive (RFC 9110).
    public func header(_ name: String) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    public static func == (lhs: HTTPRequest, rhs: HTTPRequest) -> Bool {
        lhs.method == rhs.method && lhs.path == rhs.path && lhs.body == rhs.body
            && lhs.headers.map(\.name) == rhs.headers.map(\.name) && lhs.headers.map(\.value) == rhs.headers.map(\.value)
    }
}

public struct HTTPResponse: Sendable, Equatable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    static func json(_ status: Int, _ value: JSONValue, headers: [String: String] = [:]) -> HTTPResponse {
        HTTPResponse(status: status, headers: headers.merging(["Content-Type": "application/json"]) { $1 }, body: value.encoded())
    }

    /// The bytes on the wire. Content-Length is always set, so a client can
    /// keep the connection open for its next request.
    func serialized(closing: Bool) -> Data {
        var lines = ["HTTP/1.1 \(status) \(Self.reason(status))"]
        var headers = headers
        headers["Content-Length"] = String(body.count)
        headers["Connection"] = closing ? "close" : "keep-alive"
        headers["Cache-Control"] = "no-store"
        lines += headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
        var data = Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
        data.append(body)
        return data
    }

    static func reason(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 202: "Accepted"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 408: "Request Timeout"
        case 411: "Length Required"
        case 413: "Content Too Large"
        case 415: "Unsupported Media Type"
        case 429: "Too Many Requests"
        case 431: "Request Header Fields Too Large"
        case 501: "Not Implemented"
        case 503: "Service Unavailable"
        default: "Error"
        }
    }
}

/// Reads requests from a connection's bytes as they arrive. Size limits are
/// checked before anything is buffered past them, so a client cannot make the
/// app hold a large body in memory.
struct HTTPRequestParser {
    enum Failure: Error, Equatable {
        /// Status to answer before closing the connection.
        case reject(Int)
    }

    let maximumHeaderBytes: Int
    let maximumBodyBytes: Int
    private var buffer = Data()

    init(maximumHeaderBytes: Int, maximumBodyBytes: Int) {
        self.maximumHeaderBytes = maximumHeaderBytes
        self.maximumBodyBytes = maximumBodyBytes
    }

    var hasBufferedBytes: Bool { !buffer.isEmpty }

    mutating func append(_ data: Data) {
        buffer.append(data)
    }

    /// The next complete request, or nil when more bytes are needed.
    mutating func next() throws(Failure) -> HTTPRequest? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = buffer.range(of: separator) else {
            if buffer.count > maximumHeaderBytes { throw .reject(431) }
            return nil
        }
        guard headerEnd.lowerBound - buffer.startIndex <= maximumHeaderBytes else { throw .reject(431) }
        guard let head = String(data: buffer[buffer.startIndex..<headerEnd.lowerBound], encoding: .utf8) else {
            throw .reject(400)
        }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: false)
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else { throw .reject(400) }
        var headers: [(name: String, value: String)] = []
        for line in lines {
            guard let colon = line.firstIndex(of: ":"), colon != line.startIndex,
                  !line[..<colon].contains(where: \.isWhitespace) else { throw .reject(400) }
            headers.append((String(line[..<colon]), line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)))
        }
        let request = HTTPRequest(
            method: String(requestLine[0]),
            path: String(requestLine[1].prefix { $0 != "?" }),
            headers: headers
        )

        let bodyStart = headerEnd.upperBound
        if request.header("Transfer-Encoding") != nil {
            // Every client we tested sends Content-Length; chunked bodies are
            // not worth a decoder for requests this small.
            throw .reject(411)
        }
        let length: Int
        if let value = request.header("Content-Length") {
            guard let parsed = Int(value), parsed >= 0 else { throw .reject(400) }
            length = parsed
        } else {
            length = 0
        }
        guard length <= maximumBodyBytes else { throw .reject(413) }
        guard buffer.endIndex - bodyStart >= length else { return nil }

        var complete = request
        complete.body = Data(buffer[bodyStart..<(bodyStart + length)])
        buffer = Data(buffer[(bodyStart + length)...])
        return complete
    }
}

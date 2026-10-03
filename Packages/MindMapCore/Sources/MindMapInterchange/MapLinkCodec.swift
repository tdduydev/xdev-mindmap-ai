import Compression
import Foundation
import MindMapDomain
import MindMapGraph

/// Why a map link could not be read or made (FR-IO-09, FR-CLP-01).
public enum MapLinkError: Error, Hashable, Sendable {
    /// Not a `https://xdev.asia/mindmap/m#…` link, or its fragment has the wrong shape.
    case notAMapLink
    /// The right shape, but the data does not decode: usually a link cut short when it was copied.
    case damaged
    /// Written by a newer version of the app, in a format this one does not know.
    case newerVersion
    /// Expands beyond what the app reads from a link (a small link can inflate into a huge one).
    case tooLarge
}

/// What sharing a map or a branch as a link gives (FR-CLP-01).
public enum MapLinkShare: Hashable, Sendable {
    case link(URL)
    /// Longer than `MapLinkCodec.maximumLinkLength`. Nothing is cut: the
    /// person picks a smaller share. `withoutNotes` is the same share with
    /// no notes, when that one fits.
    case tooLong(withoutNotes: URL?)
}

/// A map in a link: `https://xdev.asia/mindmap/m#1.<data>` (ADR 0012, docs/app-clip.md).
///
/// `<data>` is base64url without padding of raw DEFLATE (`COMPRESSION_ZLIB`)
/// of compact JSON. The map sits in the fragment, which a browser never sends
/// to a server, so the link works without a backend (ADR 0001). The app, the
/// App Clip and the web page in `docs/web/` read the same format.
///
/// The link carries the tree, titles, notes, URL links and the AI label; images,
/// tags, connections, floating topics and styles stay out (the sheet says so).
public enum MapLinkCodec {
    public static let currentVersion = 1
    public static let host = "xdev.asia"
    public static let path = "/mindmap/m"
    /// The whole URL, in characters [Đề xuất]. RFC 9110 §4.1 recommends that
    /// everything handles URIs of at least 8,000 octets.
    public static let maximumLinkLength = 8_000
    /// Reading stops here, so a link built to inflate into a huge payload costs at most this much memory.
    public static let maximumPayloadSize = 1_048_576
    public static let maximumTopics = 2_000
    public static let maximumDepth = 100

    // MARK: Making links

    /// The map, or the branch under `branchID`, as a link, with no length check.
    ///
    /// A branch becomes the central topic of the link, and its title the map's.
    /// Floating topics are not in a whole-map link: the link has one tree.
    /// Throws `MapLinkError.tooLarge` for a map the reader would refuse
    /// (more than `maximumTopics` topics or `maximumDepth` levels).
    public static func link(for state: GraphState, branch branchID: NodeID? = nil, includeNotes: Bool = true) throws -> URL {
        guard let startID = branchID ?? state.map.rootNodeID else { throw InterchangeError.emptyDocument }
        let nodes = try OutlineWalk.nodes(of: state, from: startID)
        guard nodes.count <= maximumTopics else { throw MapLinkError.tooLarge }
        guard let root = try nestedTopic(from: nodes, includeNotes: includeNotes) else { throw InterchangeError.emptyDocument }
        let title = branchID == nil ? state.map.title : root.t
        return try link(for: Payload(t: title, r: root))
    }

    /// The share as it would be sent, or why it is too long. Off the main
    /// actor: a large map takes a moment to compress.
    @concurrent
    public static func share(_ state: GraphState, branch branchID: NodeID? = nil) async -> MapLinkShare {
        if let url = try? fittingLink(for: state, branch: branchID, includeNotes: true) {
            return .link(url)
        }
        return .tooLong(withoutNotes: try? fittingLink(for: state, branch: branchID, includeNotes: false))
    }

    private static func fittingLink(for state: GraphState, branch branchID: NodeID?, includeNotes: Bool) throws -> URL {
        let url = try link(for: state, branch: branchID, includeNotes: includeNotes)
        guard url.absoluteString.count <= maximumLinkLength else { throw MapLinkError.tooLarge }
        return url
    }

    static func link(for payload: Payload) throws -> URL {
        let encoder = JSONEncoder()
        // Sorted for the same bytes on every run; slashes unescaped because every byte counts.
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let json = try encoder.encode(payload)
        let data = try deflate(json).base64URLEncodedString()
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        // Every base64url character is allowed in a fragment as is.
        components.percentEncodedFragment = "\(currentVersion).\(data)"
        guard let url = components.url else { throw MapLinkError.damaged }
        return url
    }

    /// The flat walk as nested topics. Built with a stack, so depth costs no recursion here.
    private static func nestedTopic(from nodes: [(MindNode, Int)], includeNotes: Bool) throws -> Topic? {
        var stack: [Topic] = []
        func closeLast() {
            let finished = stack.removeLast()
            stack[stack.count - 1].c = (stack[stack.count - 1].c ?? []) + [finished]
        }
        for (node, depth) in nodes {
            guard depth <= maximumDepth else { throw MapLinkError.tooLarge }
            while stack.count > depth { closeLast() }
            var topic = Topic(t: node.title)
            if includeNotes, let note = node.note, !note.allSatisfy(\.isWhitespace) { topic.n = note }
            // Only a link this build opens, as in the other exports.
            if let link = node.link, link.url != nil { topic.l = link.string }
            if node.metadata.origin == .ai { topic.a = 1 }
            stack.append(topic)
        }
        while stack.count > 1 { closeLast() }
        return stack.first
    }

    // MARK: Reading links

    /// Whether the URL is addressed to the map link page, before reading its fragment.
    /// The app routes such a URL here and reports anything wrong with the rest.
    public static func isMapLink(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host()?.lowercased() == host
            && (url.path() == path || url.path() == path + "/")
    }

    /// A new map from a link, never a change to an existing one.
    @concurrent
    public static func map(from url: URL, now: Date = .now) async throws(MapLinkError) -> GraphState {
        try graph(from: decode(url), now: now)
    }

    /// The payload, after every check of docs/app-clip.md, *Reading a link safely*.
    static func decode(_ url: URL) throws(MapLinkError) -> Payload {
        guard isMapLink(url), let fragment = url.fragment(percentEncoded: true) else { throw .notAMapLink }
        let parts = fragment.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, let versionText = parts.first, !versionText.isEmpty,
              versionText.allSatisfy({ $0.isASCII && $0.isNumber }),
              let encoded = parts.last, !encoded.isEmpty,
              encoded.unicodeScalars.allSatisfy(isBase64URL)
        else { throw .notAMapLink }
        // A version too long for Int is still a newer one.
        guard let version = Int(versionText) else { throw .newerVersion }
        if version > currentVersion { throw .newerVersion }
        guard version == currentVersion else { throw .notAMapLink }

        guard let compressed = Data(base64URLEncoded: String(encoded)) else { throw .damaged }
        let json = try inflate(compressed)
        // JSONDecoder recurses per level; refusing deep nesting first keeps the stack bounded.
        guard nestingDepth(of: json) <= 2 * maximumDepth + 4 else { throw .tooLarge }
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: json)
        } catch {
            throw .damaged
        }
        return payload
    }

    static func graph(from payload: Payload, now: Date = .now) throws(MapLinkError) -> GraphState {
        var entries: [(id: NodeID, parentID: NodeID?, topic: Topic)] = []
        var stack: [(topic: Topic, parentID: NodeID?, depth: Int)] = [(payload.r, nil, 0)]
        while let (topic, parentID, depth) = stack.popLast() {
            guard depth <= maximumDepth, entries.count < maximumTopics else { throw .tooLarge }
            let id = NodeID()
            entries.append((id, parentID, topic))
            // Reversed so they come off the stack in their order.
            stack.append(contentsOf: (topic.c ?? []).reversed().map { ($0, id, depth + 1) })
        }
        let rootTitle = payload.r.t ?? ""
        let title = payload.t.flatMap { $0.allSatisfy(\.isWhitespace) ? nil : $0 } ?? rootTitle
        do {
            var engine = try GraphEngine(
                state: GraphState(map: MindMap(title: title, createdAt: now)),
                clock: { now }
            )
            try engine.execute(BuildLinkedMapCommand(entries: entries))
            return engine.state
        } catch {
            throw .damaged
        }
    }

    // MARK: Format

    /// Version 1. One-letter keys because every byte counts against the length
    /// limit. Unknown keys are ignored, so version 1 can gain optional keys.
    struct Payload: Codable, Hashable {
        /// Map title.
        var t: String?
        /// Central topic.
        var r: Topic
    }

    struct Topic: Codable, Hashable {
        var t: String?
        /// Note.
        var n: String?
        /// Link URL.
        var l: String?
        /// 1 when the topic came from AI, so it keeps its label.
        var a: Int?
        /// Children, in order.
        var c: [Topic]?

        init(t: String?, n: String? = nil, l: String? = nil, a: Int? = nil, c: [Topic]? = nil) {
            self.t = t
            self.n = n
            self.l = l
            self.a = a
            self.c = c
        }
    }

    // MARK: Compression and text

    static func deflate(_ data: Data) throws -> Data {
        // DEFLATE stores incompressible input with a few bytes per block, so this always fits.
        let capacity = data.count + 1_024
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { (destination: UnsafeMutableRawBufferPointer) -> Int in
            data.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Int in
                compression_encode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    source.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { throw MapLinkError.damaged }
        return output.prefix(written)
    }

    /// The output buffer is one byte over the limit: filling it means the data
    /// would expand further, which is refused rather than read in part.
    static func inflate(_ data: Data) throws(MapLinkError) -> Data {
        let capacity = maximumPayloadSize + 1
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { (destination: UnsafeMutableRawBufferPointer) -> Int in
            data.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Int in
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    source.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { throw .damaged }
        guard written <= maximumPayloadSize else { throw .tooLarge }
        return output.prefix(written)
    }

    /// The deepest nesting of `{` and `[` outside strings.
    static func nestingDepth(of json: Data) -> Int {
        var depth = 0
        var deepest = 0
        var inString = false
        var escaped = false
        for byte in json {
            if inString {
                if escaped { escaped = false } else if byte == UInt8(ascii: "\\") { escaped = true } else if byte == UInt8(ascii: "\"") { inString = false }
                continue
            }
            switch byte {
            case UInt8(ascii: "\""): inString = true
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                depth += 1
                deepest = max(deepest, depth)
            case UInt8(ascii: "}"), UInt8(ascii: "]"): depth -= 1
            default: break
            }
        }
        return deepest
    }

    private static func isBase64URL(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "A"..."Z", "a"..."z", "0"..."9", "-", "_": true
        default: false
        }
    }
}

/// Adds every topic of a link to an empty map. Only ever run on a new map, so
/// it is not an undo step anyone sees.
private struct BuildLinkedMapCommand: GraphCommand {
    let entries: [(id: NodeID, parentID: NodeID?, topic: MapLinkCodec.Topic)]

    func execute(in transaction: inout GraphTransaction) throws {
        for (id, parentID, topic) in entries {
            let note = topic.n.flatMap { $0.allSatisfy(\.isWhitespace) ? nil : $0 }
            try AddNodeCommand(
                nodeID: id,
                parentID.map { .child(of: $0) } ?? .root,
                title: topic.t ?? "",
                note: note,
                metadata: NodeMetadata(origin: topic.a == 1 ? .ai : .imported)
            ).execute(in: &transaction)
            // A link this build would not accept is dropped, never opened.
            if let link = topic.l.flatMap(TopicLink.normalized) {
                try transaction.updateNode(id) { $0.link = link }
            }
        }
    }
}

extension Data {
    /// RFC 4648 §5, without padding.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded text: String) {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        // A length of 1 mod 4 is never valid base64; the decoder below rejects it.
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}

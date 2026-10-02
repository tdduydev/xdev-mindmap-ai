import Foundation

/// A URL on a topic (FR-ORG-26). The text is kept as stored even when this
/// build cannot open it, so a link written by a newer build survives an edit.
public struct TopicLink: Hashable, Sendable, Codable {
    public static let maximumLength = 2_048
    public static let allowedSchemes: Set<String> = ["http", "https", "mailto"]

    public let string: String

    public init(string: String) {
        self.string = string
    }

    /// Nil when the text does not parse, is too long or has another scheme.
    public var url: URL? {
        guard string.count <= Self.maximumLength,
              let url = URL(string: string),
              let scheme = url.scheme?.lowercased(), Self.allowedSchemes.contains(scheme)
        else { return nil }
        return url
    }

    /// What a person typed or pasted, as it is stored, or nil when it is not
    /// a link this build opens. `validated(_:)` says why.
    public static func normalized(_ text: String) -> TopicLink? {
        (try? validated(text)) ?? nil
    }

    /// The rules of docs/node-organization.md "Links": trimmed; a bare host
    /// gets `https://` and a bare address `mailto:`; spaces and other
    /// characters a URL cannot hold are percent-encoded; scheme and host
    /// lowercased. Nil for an empty field, which means "no link".
    public static func validated(_ text: String) throws(TopicLinkError) -> TopicLink? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme: String
        if hasScheme(trimmed) {
            withScheme = trimmed
        } else if isBareAddress(trimmed) {
            withScheme = "mailto:" + trimmed
        } else {
            withScheme = "https://" + trimmed
        }
        guard let parsed = URL(string: withScheme, encodingInvalidCharacters: true),
              var components = URLComponents(url: parsed, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased()
        else { throw .unreadable }
        guard allowedSchemes.contains(scheme) else { throw .unsupportedScheme }
        components.scheme = scheme
        if scheme == "mailto" {
            guard !components.path.isEmpty else { throw .missingAddress }
        } else {
            guard let host = components.host, !host.isEmpty else { throw .missingHost }
            components.host = host.lowercased()
        }
        guard let string = components.string else { throw .unreadable }
        guard string.count <= maximumLength else { throw .tooLong }
        let link = TopicLink(string: string)
        guard link.url != nil else { throw .unreadable }
        return link
    }

    /// `name:` at the start, but not `example.com:8080`, whose "scheme" is a host and port.
    private static func hasScheme(_ text: String) -> Bool {
        guard let colon = text.firstIndex(of: ":") else { return false }
        let scheme = text[..<colon]
        guard let first = scheme.first, first.isASCII, first.isLetter,
              scheme.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+-.".contains($0)) })
        else { return false }
        let rest = text[text.index(after: colon)...]
        let isPort = scheme.contains(".") && rest.first?.isNumber == true
        return !isPort
    }

    /// `name@example.com`: one `@`, no `/`.
    private static func isBareAddress(_ text: String) -> Bool {
        text.count(where: { $0 == "@" }) == 1 && !text.contains("/") && !text.hasPrefix("@") && !text.hasSuffix("@")
    }

    /// What VoiceOver and the help tag name the link by: the host, or the
    /// address for `mailto`; never the path or query, which can be long or private.
    public var displayName: String? {
        guard let url else { return nil }
        if url.scheme?.lowercased() == "mailto" {
            let address = URLComponents(url: url, resolvingAgainstBaseURL: false)?.path ?? ""
            return address.removingPercentEncoding ?? address
        }
        return url.host()
    }

    public var isMail: Bool { url?.scheme?.lowercased() == "mailto" }
}

/// Why a typed link was refused (FR-ORG-26).
public enum TopicLinkError: Error, Hashable, Sendable {
    /// `file:`, `javascript:`, `data:`, app schemes and the like.
    case unsupportedScheme
    case missingHost
    case missingAddress
    case tooLong
    case unreadable
}

/// The centre of a floating topic in canvas points relative to the central
/// topic's centre, y down (ADR 0010).
public struct TopicPosition: Hashable, Sendable, Codable {
    /// Far beyond any real map; keeps a corrupt value from breaking layout.
    public static let limit: Double = 100_000

    public let x: Double
    public let y: Double

    /// Non-finite values read as 0 and the rest clamp to ±`limit`, so every
    /// stored pair is drawable.
    public init(x: Double, y: Double) {
        self.x = Self.clamped(x)
        self.y = Self.clamped(y)
    }

    private static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, -limit), limit)
    }
}

/// One picture on a topic, in its own record so the topic stays small and an
/// image edit does not conflict with a title edit.
///
/// `data` is the encoded image. The graph never holds it (`GraphState` keeps
/// images without bytes); change sets carry it when an image is added, and
/// when one is removed and its bytes were known, so undo can bring it back.
public struct MindImage: Identifiable, Hashable, Sendable, Codable {
    public static let maximumAltTextLength = 250
    /// Medium, used when `displayWidth` is nil.
    public static let defaultDisplayWidth: Double = 160

    public let id: ImageID
    public let mapID: MapID
    public var nodeID: NodeID
    /// Nil when not loaded. Saving a value without bytes leaves the stored bytes alone.
    public var data: Data?
    /// `public.heic`, `public.png` or `public.jpeg`.
    public var uniformType: String
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var byteCount: Int
    /// Points on the canvas; nil is `defaultDisplayWidth`.
    public var displayWidth: Double?
    /// The person's description for VoiceOver.
    public var altText: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: ImageID = ImageID(),
        mapID: MapID,
        nodeID: NodeID,
        data: Data? = nil,
        uniformType: String = "public.heic",
        pixelWidth: Int = 0,
        pixelHeight: Int = 0,
        byteCount: Int = 0,
        displayWidth: Double? = nil,
        altText: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.mapID = mapID
        self.nodeID = nodeID
        self.data = data
        self.uniformType = uniformType
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.byteCount = byteCount
        self.displayWidth = displayWidth
        self.altText = altText
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    /// The same image without its bytes, as the graph holds it.
    public var withoutData: MindImage {
        var copy = self
        copy.data = nil
        return copy
    }

    /// Trimmed and cut to `maximumAltTextLength` characters; nil for blank text.
    public static func normalizedAltText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maximumAltTextLength))
    }
}

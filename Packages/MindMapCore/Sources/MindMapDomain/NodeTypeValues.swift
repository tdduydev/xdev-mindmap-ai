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

    /// What a person typed or pasted, as it is stored: trimmed, `https://`
    /// added to a bare host, scheme and host lowercased. Nil when the result
    /// is not a link this build opens.
    public static func normalized(_ text: String) -> TopicLink? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        let withScheme = trimmed.contains(":") ? trimmed : "https://" + trimmed
        guard var components = URLComponents(string: withScheme),
              let scheme = components.scheme?.lowercased(), allowedSchemes.contains(scheme)
        else { return nil }
        components.scheme = scheme
        if scheme == "mailto" {
            guard !components.path.isEmpty else { return nil }
        } else {
            guard let host = components.host, !host.isEmpty else { return nil }
            components.host = host.lowercased()
        }
        guard let string = components.string else { return nil }
        let link = TopicLink(string: string)
        return link.url == nil ? nil : link
    }
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

    /// Nil (Medium) for a width that is not finite or not positive.
    public static func normalizedDisplayWidth(_ width: Double?) -> Double? {
        guard let width, width.isFinite, width > 0 else { return nil }
        return width
    }

    /// Trimmed and cut to `maximumAltTextLength` characters; nil for blank text.
    public static func normalizedAltText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maximumAltTextLength))
    }
}

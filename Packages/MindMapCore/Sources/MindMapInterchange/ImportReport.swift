import Foundation

/// What a file from another app had that the new map could not keep (FR-IO-13).
///
/// Every importer keeps every topic; what it cannot carry over (a picture it
/// cannot read, an outline it would have to download) is counted here so the
/// app can say so after the import instead of dropping it without a word.
/// Importers for FreeMind, XMind and MindNode (MM-102..104) add their cases
/// to `Loss`; the app words each one.
public struct ImportReport: Hashable, Sendable {
    /// Kinds of content an importer could not carry over, in the order the
    /// summary lists them.
    public enum Loss: String, Hashable, Sendable, CaseIterable {
        /// An OPML `include` outline: its URL is kept as the topic's link,
        /// but the outline behind it is not downloaded (the app reads no network).
        case includedOutline
        /// A picture that could not be read or stored.
        case image
        /// A file attached to a topic, which maps have no place for.
        case attachment
        /// A FreeMind or Freeplane icon on a topic (MM-102); topics have
        /// one symbol of their own, and the two sets do not line up.
        case icon
    }

    public struct Entry: Hashable, Sendable {
        public let loss: Loss
        public let count: Int

        public init(loss: Loss, count: Int) {
            self.loss = loss
            self.count = count
        }
    }

    private var counts: [Loss: Int] = [:]

    public init() {}

    public mutating func record(_ loss: Loss, count: Int = 1) {
        guard count > 0 else { return }
        counts[loss, default: 0] += count
    }

    public mutating func merge(_ other: ImportReport) {
        for (loss, count) in other.counts { record(loss, count: count) }
    }

    public func count(of loss: Loss) -> Int { counts[loss] ?? 0 }

    /// Nothing was lost, so the app shows no summary.
    public var isEmpty: Bool { counts.isEmpty }

    /// One entry per kind of loss, in `Loss` order.
    public var entries: [Entry] {
        Loss.allCases.compactMap { loss in counts[loss].map { Entry(loss: loss, count: $0) } }
    }
}

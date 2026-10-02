import Foundation

/// Text reduced to what a search compares: no case, no accents, no width.
///
/// People type Vietnamese without tone marks all the time ("thiet ke" for
/// "Thiết kế"), so a search that needs the marks finds nothing.
public enum SearchText {
    public static func fold(_ text: String) -> String {
        // Diacritic folding removes combining marks, but "đ" is its own letter
        // with no decomposition, so it survives folding and needs mapping by hand.
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "đ", with: "d")
    }
}

/// What the person typed, split into folded words. Every word has to appear
/// in a text for it to match, in any order, so "ke thiet" still finds
/// "Thiết kế" and extra spaces change nothing.
public struct SearchQuery: Hashable, Sendable {
    public let terms: [String]

    public init(_ text: String) {
        terms = SearchText.fold(text)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    public var isEmpty: Bool { terms.isEmpty }

    /// `folded` must already be `SearchText.fold`ed; indexes fold once and match many times.
    public func matches(folded: String) -> Bool {
        !terms.isEmpty && terms.allSatisfy { folded.contains($0) }
    }

    public func matches(_ text: String) -> Bool {
        matches(folded: SearchText.fold(text))
    }
}

import Foundation

/// How much text one answer may hold. MCP counts characters, the chat counts
/// estimated tokens; this target knows neither unit, so the caller passes the
/// measure. Keeping `TokenEstimator` out of here keeps MindMapQuery free of AI.
public struct TextLimit: Sendable {
    /// What the whole result may cost.
    public let budget: Int
    /// What each topic costs besides its text: the bullet, indentation and the
    /// ID or handle the caller writes next to it.
    public let perTopic: Int
    private let measure: @Sendable (String) -> Int

    /// `measure` must never shrink when text grows, so a cut note can be
    /// found by halving.
    public init(budget: Int, perTopic: Int = 0, measure: @escaping @Sendable (String) -> Int) {
        self.budget = max(0, budget)
        self.perTopic = max(0, perTopic)
        self.measure = measure
    }

    public static func characters(_ budget: Int, perTopic: Int = 0) -> TextLimit {
        TextLimit(budget: budget, perTopic: perTopic) { $0.count }
    }

    public func cost(_ text: String) -> Int {
        text.isEmpty ? 0 : measure(text)
    }

    /// The longest start of `text` that costs at most `remaining`.
    func prefix(of text: String, fitting remaining: Int) -> String {
        guard remaining > 0 else { return "" }
        guard cost(text) > remaining else { return text }
        var low = 0
        var high = text.count
        while low < high {
            let middle = (low + high + 1) / 2
            if cost(String(text.prefix(middle))) <= remaining {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return String(text.prefix(low))
    }
}

import Foundation

/// How a conversation shares the model's small context window (docs/chat.md,
/// Budget) [Đề xuất]: instructions and tool schemas, two tool results, the
/// answer, and what is left for earlier turns.
public struct ChatBudget: Hashable, Sendable {
    /// Instructions and the three tool schemas, as measured by estimate.
    public static let instructionsReserve = 700
    public static let answerReserve = 600
    /// One tool result; the model usually needs a search and one read.
    public static let toolOutputLimit = 600
    public static let toolCallsPerAnswer = 2

    public let contextSize: Int
    public let toolOutput: Int

    public init(contextSize: Int?) {
        let size = contextSize ?? AIContextLimits.assumedContextSize
        self.contextSize = size
        // A smaller window than today's 4,096 tokens still leaves the answer
        // and the earlier turns some room.
        toolOutput = max(150, min(Self.toolOutputLimit, size / 7))
    }

    /// What earlier turns may cost before a question that costs `question`.
    public func historyAllowance(question: Int) -> Int {
        max(0, contextSize - Self.instructionsReserve - Self.answerReserve - toolOutput * Self.toolCallsPerAnswer - question)
    }

    /// Whether a session that already holds `used` tokens has room for a
    /// question that costs `question`, its tool results and its answer.
    public func fits(used: Int, question: Int) -> Bool {
        used + question + toolOutput * Self.toolCallsPerAnswer + Self.answerReserve <= contextSize
    }

    /// How many of the latest turns fit in `allowance`, given each turn's cost
    /// oldest first. The newest go in first; a turn that does not fit stops the
    /// count, so the model never sees a gap in the middle of the conversation.
    public static func latestTurnsFitting(_ costs: [Int], within allowance: Int) -> Int {
        var remaining = allowance
        var count = 0
        for cost in costs.reversed() {
            guard cost <= remaining else { break }
            remaining -= cost
            count += 1
        }
        return count
    }

    /// The estimated cost of a turn handed back to the model as plain text.
    public static func cost(question: String, answer: String) -> Int {
        TokenEstimator.estimate(question) + TokenEstimator.estimate(answer) + 8
    }
}

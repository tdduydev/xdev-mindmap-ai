import Foundation

// Stored as raw values that must never be renamed. These are structs, not
// enums, so a value written by a newer version on another device survives a
// round trip through this build instead of being reset to a default (Sync and
// repair in docs/node-organization.md).

/// A colour token for a topic, link, tag or boundary, from the Standard branch
/// colours plus graphite. The app maps it to `BranchColors`.
public struct TopicColor: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let blue = TopicColor(rawValue: "blue")
    public static let teal = TopicColor(rawValue: "teal")
    public static let amber = TopicColor(rawValue: "amber")
    public static let violet = TopicColor(rawValue: "violet")
    public static let rose = TopicColor(rawValue: "rose")
    public static let green = TopicColor(rawValue: "green")
    public static let graphite = TopicColor(rawValue: "graphite")

    /// In menu order; each one has a paired shape in the same order.
    public static let all: [TopicColor] = [.blue, .teal, .amber, .violet, .rose, .green, .graphite]

    /// False for a token from a newer version; it draws as the theme colour.
    public var isKnown: Bool { Self.all.contains(self) }
}

/// Whether a task is done. Anything but `done`, including a state this build
/// does not know, reads as open, so the topic stays a task.
public struct TaskState: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let open = TaskState(rawValue: "open")
    public static let done = TaskState(rawValue: "done")

    public var isDone: Bool { self == .done }
}

/// 1 high, 2 medium, 3 low, as in Reminders.
public struct TaskPriority: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let high = TaskPriority(rawValue: 1)
    public static let medium = TaskPriority(rawValue: 2)
    public static let low = TaskPriority(rawValue: 3)

    /// The level to show: a stored value above 3 reads as low, below 1 as high.
    public var level: TaskPriority {
        TaskPriority(rawValue: min(max(rawValue, 1), 3))
    }
}

public struct EdgeLineStyle: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let solid = EdgeLineStyle(rawValue: "solid")
    public static let dashed = EdgeLineStyle(rawValue: "dashed")
    public static let dotted = EdgeLineStyle(rawValue: "dotted")
}

public struct EdgeArrowHeads: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let none = EdgeArrowHeads(rawValue: "none")
    public static let end = EdgeArrowHeads(rawValue: "end")
    public static let start = EdgeArrowHeads(rawValue: "start")
    public static let both = EdgeArrowHeads(rawValue: "both")
}

/// The symbol before a topic's title: an SF Symbol name or one emoji.
public enum TopicSymbol {
    /// Trimmed; a string of only `a-z`, `0-9` and `.` is a symbol name and kept
    /// whole, anything else is an emoji and only its first grapheme is kept.
    /// Nil for blank text.
    public static func normalized(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return nil }
        return isSymbolName(trimmed) ? trimmed : String(first)
    }

    public static func isSymbolName(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { scalar in
            ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "."
        }
    }
}

/// A calendar day with no time or time zone, so a due date stays on the same
/// day wherever the device is. Stored as ISO 8601 `YYYY-MM-DD`.
public struct CalendarDay: Hashable, Sendable, Comparable {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Nil for a day that does not exist in the Gregorian calendar.
    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        let components = DateComponents(calendar: Self.gregorian, year: year, month: month, day: day)
        guard components.isValidDate else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Accepts exactly `YYYY-MM-DD`.
    public init?(isoString: String) {
        let parts = isoString.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The day `date` falls on in `calendar`, which carries the device's time zone.
    public init(_ date: Date, in calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        year = components.year ?? 1
        month = components.month ?? 1
        day = components.day ?? 1
    }

    public var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    private static let gregorian = Calendar(identifier: .gregorian)
}

extension CalendarDay: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let day = CalendarDay(isoString: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a YYYY-MM-DD day")
        }
        self = day
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(isoString)
    }
}

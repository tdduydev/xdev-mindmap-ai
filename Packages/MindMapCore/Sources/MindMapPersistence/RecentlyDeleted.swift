import Foundation

/// How long a deleted map waits in Recently Deleted before it is deleted for
/// good (FR-LIB-11, DR-07).
public enum RecentlyDeleted {
    public static let retentionDays = 30

    /// Measured in elapsed time, not calendar days: a daylight saving change or
    /// a trip across time zones must not shorten the wait.
    public static let retention: TimeInterval = TimeInterval(retentionDays) * 24 * 60 * 60

    /// Maps deleted before this moment are due to be deleted for good.
    public static func cutoff(now: Date) -> Date {
        now.addingTimeInterval(-retention)
    }

    /// When a map deleted at `deletedAt` is deleted for good.
    public static func expiry(of deletedAt: Date) -> Date {
        deletedAt.addingTimeInterval(retention)
    }

    /// Whole days left before the map goes, counted up, so a map deleted a
    /// moment ago shows 30 and one with an hour left shows 1; 0 once due.
    public static func daysLeft(deletedAt: Date, now: Date) -> Int {
        let remaining = expiry(of: deletedAt).timeIntervalSince(now)
        guard remaining > 0 else { return 0 }
        return Int((remaining / (24 * 60 * 60)).rounded(.up))
    }
}

import Foundation

/// Converts between Postgres `date` values (ISO `"yyyy-MM-dd"` strings) and
/// `Date`/display text. All vault date columns use this so JSON round-trips are
/// unambiguous (no time zone or fractional-second drift).
enum DateOnly {
    /// Fixed parser/formatter — POSIX locale, UTC, calendar-stable. Read-only
    /// after configuration, so safe to share under strict concurrency.
    nonisolated(unsafe) private static let iso: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Human display formatter — "14 Mar 1992".
    nonisolated(unsafe) private static let display: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    /// Parse an ISO `"yyyy-MM-dd"` string into a `Date` (midnight UTC).
    static func parse(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        // Tolerate a full timestamp by taking the date prefix.
        let trimmed = String(string.prefix(10))
        return iso.date(from: trimmed)
    }

    /// Format a `Date` as an ISO `"yyyy-MM-dd"` string, or nil.
    static func string(_ date: Date?) -> String? {
        guard let date else { return nil }
        return iso.string(from: date)
    }

    /// Human-readable display ("14 Mar 1992") from an ISO string.
    static func displayString(_ string: String?) -> String? {
        guard let date = parse(string) else { return nil }
        return display.string(from: date)
    }

    /// Human-readable display ("14 Mar 1992") from a `Date`.
    static func displayString(from date: Date) -> String {
        display.string(from: date)
    }
}

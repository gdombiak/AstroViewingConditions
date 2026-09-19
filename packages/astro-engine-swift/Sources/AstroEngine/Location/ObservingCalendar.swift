import Foundation

/// Gregorian calendar helper for deterministic engine logic.
public enum ObservingCalendar: Sendable {
    public static func gregorian(for timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

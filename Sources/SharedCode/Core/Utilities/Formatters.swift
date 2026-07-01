import Foundation

public struct DateFormatters {
    private enum TimeZoneDateFormatterStyle: Sendable {
        case time
        case dashboardObservingTime
        case shortDate
        case fullDate
        
        func makeFormatter(timeZone: TimeZone) -> DateFormatter {
            let formatter = DateFormatter()
            formatter.timeZone = timeZone
            
            switch self {
            case .time:
                formatter.timeStyle = .short
                formatter.dateStyle = .none
            case .dashboardObservingTime:
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "h:mm a"
            case .shortDate:
                formatter.dateFormat = "EEE, MMM d"
            case .fullDate:
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
            }
            
            return formatter
        }
    }
    
    private final class TimeZoneDateFormatterCache: @unchecked Sendable {
        private let lock = NSLock()
        private var formatters: [String: DateFormatter] = [:]
        private let style: TimeZoneDateFormatterStyle
        
        init(style: TimeZoneDateFormatterStyle) {
            self.style = style
        }
        
        func string(from date: Date, in timeZone: TimeZone?) -> String {
            let resolvedTimeZone = timeZone ?? TimeZone(secondsFromGMT: 0) ?? TimeZone.current
            let key = resolvedTimeZone.identifier
            
            lock.lock()
            defer { lock.unlock() }
            
            let formatter: DateFormatter
            if let cachedFormatter = formatters[key] {
                formatter = cachedFormatter
            } else {
                let newFormatter = style.makeFormatter(timeZone: resolvedTimeZone)
                formatters[key] = newFormatter
                formatter = newFormatter
            }
            
            return formatter.string(from: date)
        }
    }
    
    private static let timeZoneTimeFormatterCache = TimeZoneDateFormatterCache(style: .time)
    private static let dashboardObservingTimeFormatterCache = TimeZoneDateFormatterCache(style: .dashboardObservingTime)
    private static let timeZoneShortDateFormatterCache = TimeZoneDateFormatterCache(style: .shortDate)
    private static let timeZoneFullDateFormatterCache = TimeZoneDateFormatterCache(style: .fullDate)
    
    public static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
    
    public static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()
    
    public static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    public static func formatTime(_ date: Date) -> String {
        return timeFormatter.string(from: date)
    }
    
    public static func formatTime(_ date: Date, in timeZone: TimeZone?) -> String {
        timeZoneTimeFormatterCache.string(from: date, in: timeZone)
    }

    public static func formatTimeRange(
        from start: Date,
        to end: Date,
        in timeZone: TimeZone?
    ) -> String {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.timeZone = timeZone ?? TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        return formatter.string(from: start, to: end)
    }

    public static func formatDashboardObservingTimeRange(
        from start: Date,
        to end: Date,
        in timeZone: TimeZone?
    ) -> String {
        let startText = dashboardObservingTimeFormatterCache.string(from: start, in: timeZone)
        let endText = dashboardObservingTimeFormatterCache.string(from: end, in: timeZone)
        return "\(startText) – \(endText)"
    }
    
    public static func formatShortDate(_ date: Date) -> String {
        return shortDateFormatter.string(from: date)
    }
    
    public static func formatShortDate(_ date: Date, in timeZone: TimeZone?) -> String {
        timeZoneShortDateFormatterCache.string(from: date, in: timeZone)
    }
    
    public static func formatFullDate(_ date: Date) -> String {
        return fullDateFormatter.string(from: date)
    }
    
    public static func formatFullDate(_ date: Date, in timeZone: TimeZone?) -> String {
        timeZoneFullDateFormatterCache.string(from: date, in: timeZone)
    }
    
    public static func timeAgo(from date: Date) -> String {
        timeAgo(from: date, relativeTo: Date())
    }
    
    public static func timeAgo(from date: Date, relativeTo referenceDate: Date) -> String {
        guard date < referenceDate else {
            return "now"
        }

        if referenceDate.timeIntervalSince(date) < 1 {
            return "now"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: referenceDate)
    }
    
    public static func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        
        if minutes > 0 {
            return String(format: "%dm %ds", minutes, remainingSeconds)
        } else {
            return String(format: "%ds", remainingSeconds)
        }
    }
}

public struct CoordinateFormatters {
    public static func format(_ coordinate: Coordinate) -> String {
        let lat = formatLatitude(coordinate.latitude)
        let lon = formatLongitude(coordinate.longitude)
        return "\(lat), \(lon)"
    }
    
    public static func formatLatitude(_ latitude: Double) -> String {
        let direction = latitude >= 0 ? "N" : "S"
        return String(format: "%.4f° %@", abs(latitude), direction)
    }
    
    public static func formatLongitude(_ longitude: Double) -> String {
        let direction = longitude >= 0 ? "E" : "W"
        return String(format: "%.4f° %@", abs(longitude), direction)
    }
}

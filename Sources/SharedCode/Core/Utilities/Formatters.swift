import Foundation

public struct DateFormatters {
    private final class TimeZoneTimeFormatterCache: @unchecked Sendable {
        private let lock = NSLock()
        private var formatters: [String: DateFormatter] = [:]
        
        func string(from date: Date, in timeZone: TimeZone?) -> String {
            let resolvedTimeZone = timeZone ?? TimeZone(identifier: "UTC")!
            let key = resolvedTimeZone.identifier
            
            lock.lock()
            defer { lock.unlock() }
            
            let formatter: DateFormatter
            if let cachedFormatter = formatters[key] {
                formatter = cachedFormatter
            } else {
                let newFormatter = DateFormatter()
                newFormatter.timeStyle = .short
                newFormatter.dateStyle = .none
                newFormatter.timeZone = resolvedTimeZone
                formatters[key] = newFormatter
                formatter = newFormatter
            }
            
            return formatter.string(from: date)
        }
    }
    
    private static let timeZoneTimeFormatterCache = TimeZoneTimeFormatterCache()
    
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
    
    public static func formatShortDate(_ date: Date) -> String {
        return shortDateFormatter.string(from: date)
    }
    
    public static func formatShortDate(_ date: Date, in timeZone: TimeZone?) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        formatter.timeZone = timeZone ?? TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
    
    public static func formatFullDate(_ date: Date) -> String {
        return fullDateFormatter.string(from: date)
    }
    
    public static func formatFullDate(_ date: Date, in timeZone: TimeZone?) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = timeZone ?? TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
    
    public static func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
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

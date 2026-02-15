import Foundation

public struct DateFormatters {
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
    
    public static func formatShortDate(_ date: Date) -> String {
        return shortDateFormatter.string(from: date)
    }
    
    public static func formatFullDate(_ date: Date) -> String {
        return fullDateFormatter.string(from: date)
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

import Foundation
import CoreLocation

public struct LocationTimeZoneResolver {
    
    /// Resolves the timezone for a given latitude/longitude using CLGeocoder.
    /// Falls back to UTC if resolution fails.
    public static func resolve(latitude: Double, longitude: Double) async -> TimeZone {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let geocoder = CLGeocoder()
        
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let placemark = placemarks.first,
               let timeZone = placemark.timeZone {
                return timeZone
            }
        } catch {
            print("LocationTimeZoneResolver: Failed to resolve timezone for (\(latitude), \(longitude)): \(error)")
        }
        
        // Fallback: approximate timezone from longitude
        // Each 15 degrees of longitude ≈ 1 hour offset from UTC
        let offsetHours = Int(round(longitude / 15.0))
        let offsetSeconds = offsetHours * 3600
        return TimeZone(secondsFromGMT: offsetSeconds) ?? TimeZone(identifier: "UTC")!
    }
    
    /// Creates a calendar configured for the given timezone.
    public static func calendar(for timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

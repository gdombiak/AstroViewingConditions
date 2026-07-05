import Foundation
import CoreLocation
import os

private let timeZoneLogger = Logger(
    subsystem: "com.astroviewing.conditions",
    category: "LocationTimeZoneResolver"
)

public struct LocationTimeZoneResolver {
    public typealias Geocoder = @Sendable (CLLocation) async throws -> TimeZone?
    public static let timeout: TimeInterval = 4
    
    /// Resolves the timezone for a given latitude/longitude using CLGeocoder.
    /// Falls back to a longitude-based fixed offset if resolution fails.
    public static func resolve(
        latitude: Double,
        longitude: Double,
        timeout: TimeInterval = Self.timeout,
        geocoder: @escaping Geocoder = { location in
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
            return placemarks.first?.timeZone
        }
    ) async -> TimeZone {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let fallback = approximate(longitude: longitude)

        do {
            if let timeZone = try await AsyncTimeout.run(
                seconds: timeout,
                operation: { try await geocoder(location) }
            ) {
                return timeZone
            }
            timeZoneLogger.debug(
                "Geocoder returned no timezone; using approximate timezone \(fallback.identifier, privacy: .public)"
            )
        } catch {
            if error is CancellationError {
                // Cancellation is normally intentional and does not need diagnostic noise.
            } else if error is TimeoutError {
                timeZoneLogger.notice(
                    "Timezone geocoder timed out; using approximate timezone \(fallback.identifier, privacy: .public)"
                )
            } else {
                timeZoneLogger.debug(
                    "Timezone geocoder failed: \(error.localizedDescription, privacy: .public); using approximate timezone \(fallback.identifier, privacy: .public)"
                )
            }
        }

        return fallback
    }
    
    /// Approximates a timezone from longitude when a network/geocoder result is unavailable.
    public static func approximate(longitude: Double) -> TimeZone {
        // Each 15 degrees of longitude is roughly 1 hour offset from UTC.
        let offsetHours = Int(round(longitude / 15.0))
        let offsetSeconds = offsetHours * 3600
        return TimeZone(secondsFromGMT: offsetSeconds) ?? TimeZone(secondsFromGMT: 0) ?? TimeZone.current
    }
    
    /// Creates a calendar configured for the given timezone.
    public static func calendar(for timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

import Foundation

/// Closed-form equatorial-to-horizontal conversion for fixed catalog coordinates.
///
/// Deterministic: no ephemeris provider, no catalog access, no network. Altitude is
/// geometric — production applies no refraction, parallax, proper motion or
/// precession, and treats UT1 as UTC. See contracts/procedures/deep-sky-observation.md.
public enum HorizontalCoordinates {
    public struct Position: Sendable, Hashable {
        /// Geometric altitude in degrees.
        public let altitude: Double
        /// Azimuth in degrees from north, increasing eastward, in `0..<360`.
        public let azimuth: Double

        public init(altitude: Double, azimuth: Double) {
            self.altitude = altitude
            self.azimuth = azimuth
        }
    }

    public static func position(
        rightAscensionHours: Double,
        declinationDegrees: Double,
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        at date: Date
    ) -> Position {
        let julianDate = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let daysSinceJ2000 = julianDate - 2_451_545.0
        let greenwichSiderealDegrees = normalizedDegrees(280.46061837 + 360.98564736629 * daysSinceJ2000)
        let localSiderealDegrees = normalizedDegrees(greenwichSiderealDegrees + longitudeDegrees)
        let hourAngle = radians(normalizedSignedDegrees(localSiderealDegrees - rightAscensionHours * 15))
        let declination = radians(declinationDegrees)
        let latitude = radians(latitudeDegrees)

        // Clamp: binary64 can push the spherical identity outside [-1, 1].
        let sineAltitude = min(max(
            sin(declination) * sin(latitude)
                + cos(declination) * cos(latitude) * cos(hourAngle),
            -1
        ), 1)
        let altitude = asin(sineAltitude)
        let azimuth = atan2(
            sin(hourAngle),
            cos(hourAngle) * sin(latitude) - tan(declination) * cos(latitude)
        ) + .pi

        return Position(altitude: degrees(altitude), azimuth: normalizedDegrees(degrees(azimuth)))
    }

    /// Eight-point compass code for an azimuth in degrees. Objective code, not copy.
    public static func compassDirection(forAzimuth azimuth: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return directions[Int((normalizedDegrees(azimuth) + 22.5) / 45) % directions.count]
    }

    static func normalizedDegrees(_ value: Double) -> Double {
        let result = value.truncatingRemainder(dividingBy: 360)
        return result >= 0 ? result : result + 360
    }

    static func normalizedSignedDegrees(_ value: Double) -> Double {
        let normalized = normalizedDegrees(value)
        return normalized > 180 ? normalized - 360 : normalized
    }

    static func radians(_ value: Double) -> Double { value * .pi / 180 }
    static func degrees(_ value: Double) -> Double { value * 180 / .pi }
}

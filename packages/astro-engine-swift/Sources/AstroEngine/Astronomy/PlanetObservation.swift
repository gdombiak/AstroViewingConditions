import Foundation

/// Bodies of the production low-precision orbital-element model.
///
/// `earth` is not a target: it exists only because the model derives the
/// geocentric Sun vector from Earth's heliocentric elements, exactly as
/// production does. The user-facing recommendation candidates are
/// `recommendationCandidates`.
public enum PlanetBody: String, Sendable, Hashable, CaseIterable {
    case earth
    case venus
    case mars
    case jupiter
    case saturn

    /// Venus, Mars, Jupiter and Saturn — the production `catalog.solar_system`
    /// planet rows. Mercury, Uranus and Neptune are not production candidates
    /// and are deliberately absent from the model.
    public static let recommendationCandidates: [PlanetBody] = [.venus, .mars, .jupiter, .saturn]
}

/// One time-stamped planet position sample.
///
/// `solarElongation` is always produced by this sampler; the deterministic
/// scorer accepts a missing value because injected facts may omit it.
public struct PlanetObservationSample: Sendable, Hashable {
    public let time: Date
    /// Geometric altitude in degrees. No refraction, no parallax.
    public let altitude: Double
    /// Azimuth in degrees from north, increasing eastward, in `0..<360`.
    public let azimuth: Double
    /// Geocentric Sun–planet angular separation in degrees, in `0...180`.
    public let solarElongation: Double

    public init(time: Date, altitude: Double, azimuth: Double, solarElongation: Double) {
        self.time = time
        self.altitude = altitude
        self.azimuth = azimuth
        self.solarElongation = solarElongation
    }
}

/// Production low-precision planet astronomy, without host recommendation types.
///
/// Portable contract: contracts/procedures/planet-observation.md. This is the
/// model production ships — Schlyter's low-precision orbital elements with the
/// `JD - 2451543.5` day number, one Kepler correction term, no light-time and no
/// refraction. It is deliberately *not* an ephemeris: replacing it would move
/// every altitude and therefore every planet score.
///
/// The 900 s cadence, the two-hour lead before astronomical night, the one-hour
/// trail after it and the inclusive `while time <= end` endpoint are the
/// production quirks of `LowPrecisionPlanetAstronomyProvider` and are preserved.
public struct LowPrecisionPlanetObservationSampler: Sendable {
    /// Production cadence of `LowPrecisionPlanetAstronomyProvider`.
    public static let defaultSampleInterval: TimeInterval = 15 * 60
    /// Sampling starts this far before astronomical-night start.
    public static let leadSeconds: TimeInterval = 2 * 3600
    /// Sampling ends this far after astronomical-night end.
    public static let trailSeconds: TimeInterval = 60 * 60

    private let sampleInterval: TimeInterval

    public init(sampleInterval: TimeInterval = LowPrecisionPlanetObservationSampler.defaultSampleInterval) {
        self.sampleInterval = sampleInterval
    }

    public static func sampleStart(nightStart: Date) -> Date {
        nightStart.addingTimeInterval(-leadSeconds)
    }

    public static func sampleEnd(nightEnd: Date) -> Date {
        nightEnd.addingTimeInterval(trailSeconds)
    }

    /// `nil` reproduces the production `guard end > start` bail-out: an interval
    /// inverted by more than `leadSeconds + trailSeconds` yields no observation
    /// at all, which is not the same as an empty sample array.
    public func samples(
        body: PlanetBody,
        latitude: Double,
        longitude: Double,
        nightStart: Date,
        nightEnd: Date
    ) -> [PlanetObservationSample]? {
        let start = Self.sampleStart(nightStart: nightStart)
        let end = Self.sampleEnd(nightEnd: nightEnd)
        guard end > start else { return nil }

        var samples: [PlanetObservationSample] = []
        var time = start

        while time <= end {
            samples.append(position(
                body: body,
                latitude: latitude,
                longitude: longitude,
                at: time
            ))
            time = time.addingTimeInterval(sampleInterval)
        }

        return samples
    }

    /// Geocentric horizontal coordinates plus solar elongation at one instant.
    ///
    /// Operation ordering is load-bearing: the equatorial rotation, the
    /// `atan2` pair and the `degrees(...) + 180` azimuth normalization are
    /// reproduced from production rather than re-derived.
    public func position(
        body: PlanetBody,
        latitude: Double,
        longitude: Double,
        at date: Date
    ) -> PlanetObservationSample {
        let jd = Self.julianDate(from: date)
        // These low-precision orbital elements use Schlyter's day-number convention:
        // d = JD - 2451543.5 (rather than the J2000.0 epoch JD 2451545.0).
        let d = jd - 2_451_543.5
        let sunGeocentric = PlanetOrbitalElements.elements(for: .earth, schlyterDayNumber: d).heliocentricCoordinates()
        let planetCoordinates = PlanetOrbitalElements.elements(for: body, schlyterDayNumber: d).heliocentricCoordinates()

        let x = planetCoordinates.x + sunGeocentric.x
        let y = planetCoordinates.y + sunGeocentric.y
        let z = planetCoordinates.z + sunGeocentric.z
        let obliquity = Self.radians(23.4393 - 3.563e-7 * d)

        let equatorialX = x
        let equatorialY = y * cos(obliquity) - z * sin(obliquity)
        let equatorialZ = y * sin(obliquity) + z * cos(obliquity)
        let rightAscension = atan2(equatorialY, equatorialX)
        let declination = atan2(equatorialZ, sqrt(equatorialX * equatorialX + equatorialY * equatorialY))

        let localSiderealTime = Self.radians(Self.normalizedDegrees(
            280.460_618_37 + 360.985_647_366_29 * (jd - 2_451_545.0) + longitude
        ))
        let hourAngle = Self.normalizedRadians(localSiderealTime - rightAscension)
        let latitudeRadians = Self.radians(latitude)

        let altitude = asin(
            sin(declination) * sin(latitudeRadians)
            + cos(declination) * cos(latitudeRadians) * cos(hourAngle)
        )
        let azimuth = atan2(
            sin(hourAngle),
            cos(hourAngle) * sin(latitudeRadians) - tan(declination) * cos(latitudeRadians)
        )

        return PlanetObservationSample(
            time: date,
            altitude: Self.degrees(altitude),
            azimuth: Self.normalizedDegrees(Self.degrees(azimuth) + 180),
            solarElongation: Self.angularSeparation(
                first: (x, y, z),
                second: sunGeocentric
            )
        )
    }

    static func angularSeparation(
        first: (x: Double, y: Double, z: Double),
        second: (x: Double, y: Double, z: Double)
    ) -> Double {
        let dotProduct = first.x * second.x + first.y * second.y + first.z * second.z
        let firstMagnitude = sqrt(first.x * first.x + first.y * first.y + first.z * first.z)
        let secondMagnitude = sqrt(second.x * second.x + second.y * second.y + second.z * second.z)
        guard firstMagnitude > 0, secondMagnitude > 0 else { return 0 }

        let cosine = min(max(dotProduct / (firstMagnitude * secondMagnitude), -1), 1)
        return degrees(acos(cosine))
    }

    static func julianDate(from date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400 + 2_440_587.5
    }

    static func radians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }

    static func degrees(_ radians: Double) -> Double {
        radians * 180 / .pi
    }

    static func normalizedDegrees(_ degrees: Double) -> Double {
        (degrees.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
    }

    static func normalizedRadians(_ radians: Double) -> Double {
        let twoPi = 2 * Double.pi
        return (radians.truncatingRemainder(dividingBy: twoPi) + twoPi)
            .truncatingRemainder(dividingBy: twoPi)
    }
}

/// Schlyter low-precision orbital elements, reproduced from production.
///
/// The eccentric-anomaly solution is the single-correction approximation
/// production ships, not an iterated Kepler solve.
struct PlanetOrbitalElements {
    let longitudeOfAscendingNode: Double
    let inclination: Double
    let argumentOfPerihelion: Double
    let semiMajorAxis: Double
    let eccentricity: Double
    let meanAnomaly: Double

    static func elements(for planet: PlanetBody, schlyterDayNumber d: Double) -> PlanetOrbitalElements {
        switch planet {
        case .earth:
            return PlanetOrbitalElements(
                longitudeOfAscendingNode: 0,
                inclination: 0,
                argumentOfPerihelion: 282.9404 + 4.70935e-5 * d,
                semiMajorAxis: 1,
                eccentricity: 0.016709 - 1.151e-9 * d,
                meanAnomaly: 356.0470 + 0.9856002585 * d
            )
        case .venus:
            return PlanetOrbitalElements(
                longitudeOfAscendingNode: 76.6799 + 2.46590e-5 * d,
                inclination: 3.3946 + 2.75e-8 * d,
                argumentOfPerihelion: 54.8910 + 1.38374e-5 * d,
                semiMajorAxis: 0.723330,
                eccentricity: 0.006773 - 1.302e-9 * d,
                meanAnomaly: 48.0052 + 1.6021302244 * d
            )
        case .mars:
            return PlanetOrbitalElements(
                longitudeOfAscendingNode: 49.5574 + 2.11081e-5 * d,
                inclination: 1.8497 - 1.78e-8 * d,
                argumentOfPerihelion: 286.5016 + 2.92961e-5 * d,
                semiMajorAxis: 1.523688,
                eccentricity: 0.093405 + 2.516e-9 * d,
                meanAnomaly: 18.6021 + 0.5240207766 * d
            )
        case .jupiter:
            return PlanetOrbitalElements(
                longitudeOfAscendingNode: 100.4542 + 2.76854e-5 * d,
                inclination: 1.3030 - 1.557e-7 * d,
                argumentOfPerihelion: 273.8777 + 1.64505e-5 * d,
                semiMajorAxis: 5.20256,
                eccentricity: 0.048498 + 4.469e-9 * d,
                meanAnomaly: 19.8950 + 0.0830853001 * d
            )
        case .saturn:
            return PlanetOrbitalElements(
                longitudeOfAscendingNode: 113.6634 + 2.38980e-5 * d,
                inclination: 2.4886 - 1.081e-7 * d,
                argumentOfPerihelion: 339.3939 + 2.97661e-5 * d,
                semiMajorAxis: 9.55475,
                eccentricity: 0.055546 - 9.499e-9 * d,
                meanAnomaly: 316.9670 + 0.0334442282 * d
            )
        }
    }

    func heliocentricCoordinates() -> (x: Double, y: Double, z: Double) {
        let meanAnomalyRadians = Self.radians(Self.normalizedDegrees(meanAnomaly))
        let eccentricAnomaly = meanAnomalyRadians
            + eccentricity * sin(meanAnomalyRadians) * (1 + eccentricity * cos(meanAnomalyRadians))

        let xv = semiMajorAxis * (cos(eccentricAnomaly) - eccentricity)
        let yv = semiMajorAxis * sqrt(1 - eccentricity * eccentricity) * sin(eccentricAnomaly)
        let trueAnomaly = atan2(yv, xv)
        let radius = sqrt(xv * xv + yv * yv)

        let node = Self.radians(longitudeOfAscendingNode)
        let inclinationRadians = Self.radians(inclination)
        let argument = trueAnomaly + Self.radians(argumentOfPerihelion)

        let x = radius * (cos(node) * cos(argument) - sin(node) * sin(argument) * cos(inclinationRadians))
        let y = radius * (sin(node) * cos(argument) + cos(node) * sin(argument) * cos(inclinationRadians))
        let z = radius * sin(argument) * sin(inclinationRadians)

        return (x, y, z)
    }

    private static func radians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }

    private static func normalizedDegrees(_ degrees: Double) -> Double {
        (degrees.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
    }
}

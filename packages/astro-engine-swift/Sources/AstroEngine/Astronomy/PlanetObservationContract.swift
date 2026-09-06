import Foundation
import CoreFoundation

public struct PlanetObservationInputError: Error, Sendable {
    public let code: String
    public let message: String

    init() {
        self.code = "validation"
        self.message = "invalid \(PlanetObservationContract.capabilityID) input"
    }

    init(sampleCap maximum: Int) {
        self.code = "sample_cap"
        self.message = "\(PlanetObservationContract.capabilityID) exceeds the 1.0 sample cap (\(maximum) samples)"
    }
}

/// Strict transport for the live planet observation fact bundle.
///
/// Normative procedure: contracts/procedures/planet-observation.md.
/// Provider-derived: this runs the production low-precision orbital-element
/// model over the production sampling span. Deterministic scoring consumes the
/// result through `targets.planet_recommendation`.
public enum PlanetObservationContract {
    public static let capabilityID = "astronomy.planet_observation"

    /// Astronomy-namespace instant window, matching `astronomy.sun_events`,
    /// `astronomy.moon_info`, `astronomy.moon_series` and
    /// `astronomy.moon_observation`.
    static let earliestInstant = Date(timeIntervalSince1970: 946_684_800)      // 2000-01-01T00:00:00Z
    static let latestInstant = Date(timeIntervalSince1970: 2_524_607_999)      // 2049-12-31T23:59:59Z

    /// Bounded live night interval, the same 26-hour bound the rest of the
    /// namespace uses for one caller-resolved local night. Inverted intervals
    /// are permitted: production still samples one until the interval is
    /// inverted by more than `lead + trail`, and then yields no observation.
    public static let maxSpanSeconds: TimeInterval = 26 * 3600

    /// One day of one-minute cadence over the sampling span. Production requests
    /// one astronomical night at the 900 s cadence — at most ~70 samples — so
    /// this admits every product request by more than an order of magnitude
    /// while bounding orbital-element work.
    public static let maxSampleCount = 1_440

    /// The public user-facing candidates. `earth` exists in the model only to
    /// supply the geocentric Sun vector and is not a target.
    public static let supportedTargetIDs: [String] =
        PlanetBody.recommendationCandidates.map(\.rawValue)

    public static func evaluate(_ input: [String: Any]) throws -> [String: Any] {
        let allowed: Set<String> = [
            "target_id", "latitude", "longitude", "night_start", "night_end", "sample_interval_seconds",
        ]
        let keys = Set(input.keys)
        guard keys.isSubset(of: allowed),
              keys.isSuperset(of: ["target_id", "latitude", "longitude", "night_start", "night_end"]) else {
            throw PlanetObservationInputError()
        }
        let body = try planetBody(input["target_id"])
        let latitude = try number(input["latitude"])
        let longitude = try number(input["longitude"])
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw PlanetObservationInputError()
        }
        let sampleInterval = try input["sample_interval_seconds"].map { try number($0) }
            ?? LowPrecisionPlanetObservationSampler.defaultSampleInterval
        guard sampleInterval > 0, sampleInterval <= maxSpanSeconds else {
            throw PlanetObservationInputError()
        }

        let nightStart = try date(input["night_start"])
        let nightEnd = try date(input["night_end"])
        guard nightEnd.timeIntervalSince(nightStart) <= maxSpanSeconds else {
            throw PlanetObservationInputError()
        }
        let start = LowPrecisionPlanetObservationSampler.sampleStart(nightStart: nightStart)
        let end = LowPrecisionPlanetObservationSampler.sampleEnd(nightEnd: nightEnd)
        guard !DeepSkyObservationContract.exceedsSampleCap(
            start: start,
            end: end,
            sampleInterval: sampleInterval,
            maximum: maxSampleCount
        ) else {
            throw PlanetObservationInputError(sampleCap: maxSampleCount)
        }
        // Whole-second output must remain strictly ordered and composable with
        // targets.planet_recommendation. Integral steps from a whole-second
        // origin are exact on both epochs throughout the bounded date range;
        // fractional steps can floor to duplicate instants.
        guard sampleInterval.rounded(.towardZero) == sampleInterval else {
            throw PlanetObservationInputError()
        }

        let samples = LowPrecisionPlanetObservationSampler(sampleInterval: sampleInterval)
            .samples(
                body: body,
                latitude: latitude,
                longitude: longitude,
                nightStart: nightStart,
                nightEnd: nightEnd
            )

        var result: [String: Any] = [
            "target_id": body.rawValue,
            "night_start": timestamp(nightStart),
            "night_end": timestamp(nightEnd),
        ]
        guard let samples else {
            result["observation"] = NSNull()
            return result
        }
        result["observation"] = [
            "sample_start": timestamp(start),
            "sample_end": timestamp(end),
            "samples": samples.map { sample -> [String: Any] in
                [
                    "time": timestamp(sample.time),
                    "altitude": sample.altitude,
                    "azimuth": sample.azimuth,
                    "solar_elongation": sample.solarElongation,
                ]
            },
        ] as [String: Any]
        return result
    }

    private static func planetBody(_ value: Any?) throws -> PlanetBody {
        guard let text = value as? String,
              supportedTargetIDs.contains(text),
              let body = PlanetBody(rawValue: text) else {
            throw PlanetObservationInputError()
        }
        return body
    }

    private static func number(_ value: Any?) throws -> Double {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else { throw PlanetObservationInputError() }
        return number.doubleValue
    }

    private static func formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    private static func date(_ value: Any?) throws -> Date {
        guard let text = value as? String,
              text.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"#, options: .regularExpression) != nil,
              let date = formatter().date(from: text), formatter().string(from: date) == text,
              date >= earliestInstant, date <= latestInstant else {
            throw PlanetObservationInputError()
        }
        return date
    }

    /// Sample instants are whole seconds by construction; the sampling span can
    /// still reach two hours before and one hour after the accepted instant
    /// window, which the transport reports rather than clamps.
    private static func timestamp(_ value: Date) -> String {
        formatter().string(from: Date(timeIntervalSince1970: value.timeIntervalSince1970.rounded(.down)))
    }
}

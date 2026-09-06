import Foundation
import CoreFoundation

public struct MoonObservationInputError: Error, Sendable {
    public let code: String
    public let message: String

    init() {
        self.code = "validation"
        self.message = "invalid \(MoonObservationContract.capabilityID) input"
    }

    init(sampleCap maximum: Int) {
        self.code = "sample_cap"
        self.message = "\(MoonObservationContract.capabilityID) exceeds the 1.0 sample cap (\(maximum) samples)"
    }

    init(engineFailure detail: String) {
        self.code = "engine_failure"
        self.message = detail
    }
}

/// Strict transport for the live lunar observation fact bundle.
///
/// Normative procedure: contracts/procedures/moon-observation.md. Provider-derived: this computes night-scoped
/// facts using the production analytic SunCalc model. Deterministic scoring consumes
/// the result through `targets.moon_recommendation`.
public enum MoonObservationContract {
    public static let capabilityID = "astronomy.moon_observation"

    /// Astronomy-namespace instant window, matching `astronomy.sun_events`,
    /// `astronomy.moon_info` and `astronomy.moon_series`.
    static let earliestInstant = Date(timeIntervalSince1970: 946_684_800)      // 2000-01-01T00:00:00Z
    static let latestInstant = Date(timeIntervalSince1970: 2_524_607_999)      // 2049-12-31T23:59:59Z

    /// Bounded live interval, the same 26-hour bound `astronomy.sun_events` uses
    /// for one caller-resolved local day. Inverted intervals are permitted: the
    /// production sampler yields no position samples for one and still runs the
    /// rise/set search over `max(span, sampleInterval)`.
    public static let maxSpanSeconds: TimeInterval = 26 * 3600

    /// One day of one-minute cadence. Production requests one astronomical night
    /// at the 1800 s cadence — at most ~53 samples — so this admits every product
    /// request by more than an order of magnitude while bounding ephemeris work.
    public static let maxSampleCount = 1_440

    public static func evaluate(_ input: [String: Any]) throws -> [String: Any] {
        let allowed: Set<String> = [
            "latitude", "longitude", "night_start", "night_end", "sample_interval_seconds",
        ]
        let keys = Set(input.keys)
        guard keys.isSubset(of: allowed),
              keys.isSuperset(of: ["latitude", "longitude", "night_start", "night_end"]) else {
            throw MoonObservationInputError()
        }
        let latitude = try number(input["latitude"])
        let longitude = try number(input["longitude"])
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw MoonObservationInputError()
        }
        let sampleInterval = try input["sample_interval_seconds"].map { try number($0) }
            ?? SunCalcMoonObservationSampler.defaultSampleInterval
        // The cadence is also the minimum MoonTimes search duration.
        guard sampleInterval > 0, sampleInterval <= maxSpanSeconds else {
            throw MoonObservationInputError()
        }

        let start = try date(input["night_start"])
        let end = try date(input["night_end"])
        guard end.timeIntervalSince(start) <= maxSpanSeconds else { throw MoonObservationInputError() }
        let span = end.timeIntervalSince(start)
        let reservesEndSample = span > 0 && span.truncatingRemainder(dividingBy: sampleInterval) != 0
        guard !DeepSkyObservationContract.exceedsSampleCap(
            start: start,
            end: end,
            sampleInterval: sampleInterval,
            maximum: maxSampleCount - (reservesEndSample ? 1 : 0)
        ) else {
            throw MoonObservationInputError(sampleCap: maxSampleCount)
        }
        // Whole-second output must remain strictly ordered and composable with
        // targets.moon_recommendation. Integral steps are exact on both epochs
        // throughout the bounded date range; fractional steps can floor to
        // duplicate instants or accumulate differently between hosts.
        guard sampleInterval.rounded(.towardZero) == sampleInterval else {
            throw MoonObservationInputError()
        }

        let observation: MoonObservationData
        do {
            observation = try SunCalcMoonObservationSampler(sampleInterval: sampleInterval,
                                                            timeZone: TimeZone(secondsFromGMT: 0))
                .observation(latitude: latitude, longitude: longitude, nightStart: start, nightEnd: end)
        } catch {
            throw MoonObservationInputError(engineFailure: "moon observation sampling failed")
        }

        return [
            "night_start": timestamp(start),
            "night_end": timestamp(end),
            "phase": observation.phase,
            "illumination": observation.illumination,
            "rise": observation.rise.map { timestamp($0) as Any } ?? NSNull(),
            "set": observation.set.map { timestamp($0) as Any } ?? NSNull(),
            "always_up": observation.alwaysUp,
            "always_down": observation.alwaysDown,
            "samples": observation.positionSamples.map { sample -> [String: Any] in
                [
                    "time": timestamp(sample.time),
                    "altitude": sample.altitude,
                    "azimuth": sample.azimuth.map { $0 as Any } ?? NSNull(),
                ]
            },
        ]
    }

    private static func number(_ value: Any?) throws -> Double {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else { throw MoonObservationInputError() }
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
            throw MoonObservationInputError()
        }
        return date
    }

    /// Rise/set instants are continuous; the transport floors to whole seconds.
    private static func timestamp(_ value: Date) -> String {
        formatter().string(from: Date(timeIntervalSince1970: value.timeIntervalSince1970.rounded(.down)))
    }
}

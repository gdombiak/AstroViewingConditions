import Foundation
import CoreFoundation

public struct DeepSkyObservationInputError: Error, Sendable {
    public let code: String
    public let message: String

    init(_ capability: String) {
        self.code = "validation"
        self.message = "invalid \(capability) input"
    }

    init(sampleCap capability: String, maximum: Int) {
        self.code = "sample_cap"
        self.message = "\(capability) exceeds the 1.0 sample cap (\(maximum) samples)"
    }
}

/// Strict transport adapters. Production callers use the typed pure API, which
/// keeps full binary64 instants; transport floors timestamps to whole seconds.
public enum DeepSkyObservationContract {
    public static let horizontalPositionID = "astronomy.horizontal_position"
    public static let deepSkyWindowsID = "targets.deep_sky_windows"
    public static let capabilityIDs = [horizontalPositionID, deepSkyWindowsID]

    /// Fixed modern product range, 2000-01-01T00:00:00Z through
    /// 2499-12-31T23:59:59Z inclusive. This is deliberately not a historical
    /// astronomy range: the lower bound sits well after the 1582 Gregorian
    /// cutover, where Foundation falls back to the Julian calendar and Python's
    /// `datetime` stays proleptic Gregorian, so the two hosts would resolve the
    /// same string to different instants. See the procedure.
    static let earliestInstant = Date(timeIntervalSince1970: 946_684_800)
    static let latestInstant = Date(timeIntervalSince1970: 16_725_225_599)

    /// 1.0 capability cap on sampling work: seven days of one-minute cadence. The
    /// production geometry is a single astronomical night at the 900 s default, at
    /// most ~96 samples even for a maximal polar night, so this admits every
    /// product request by more than two orders of magnitude while bounding
    /// worst-case work.
    public static let maxSampleCount = 10_080

    /// Capability preflight. Bounded work: one ULP query, one division and a few
    /// comparisons; it never runs the sampling loop. Mirrors
    /// `GeographicGridGenerator.exceedsContractPointCap`.
    ///
    /// An inverted interval is not a cap: it yields no samples and does no work,
    /// the same way non-positive grid radius/spacing is not a cap. A step too
    /// small to advance binary64 at the largest magnitude in range would never
    /// terminate the loop, so it counts as unbounded; checking the
    /// larger-magnitude endpoint is sufficient because the ULP is monotonic in
    /// magnitude.
    public static func exceedsSampleCap(
        start: Date,
        end: Date,
        sampleInterval: TimeInterval
    ) -> Bool {
        exceedsSampleCap(start: start, end: end, sampleInterval: sampleInterval, maximum: maxSampleCount)
    }

    /// Same preflight against a caller-supplied cap. `astronomy.moon_observation`
    /// reuses it with its own live-sampling maximum.
    public static func exceedsSampleCap(
        start: Date,
        end: Date,
        sampleInterval: TimeInterval,
        maximum: Int
    ) -> Bool {
        let span = end.timeIntervalSince(start)
        guard span >= 0 else { return false }
        let startSeconds = start.timeIntervalSinceReferenceDate
        let endSeconds = end.timeIntervalSinceReferenceDate
        let pivot = abs(startSeconds) >= abs(endSeconds) ? startSeconds : endSeconds
        guard pivot + sampleInterval > pivot else { return true }
        // `floor(span / sampleInterval) + 1` counts the mathematical series
        // `start + k * interval`, which the repeated-addition loop does not follow:
        // every `time + interval` is rounded to nearest, so the realized step can
        // be up to half a ULP smaller than requested and the loop can emit more
        // samples than that quotient predicts. Bound with the smallest step the
        // loop can take.
        let effectiveInterval = sampleInterval - abs(pivot).ulp / 2
        guard effectiveInterval > 0 else { return true }
        let quotient = span / effectiveInterval
        // Iterations are at most floor(quotient) + 1, so that is <= max <=> quotient < max.
        return !(quotient.isFinite && quotient < Double(maximum))
    }

    public static func evaluate(
        _ capability: String,
        input: [String: Any],
        catalog: [DeepSkyCatalogEntry]
    ) throws -> [String: Any] {
        switch capability {
        case horizontalPositionID:
            return try horizontalPosition(input)
        case deepSkyWindowsID:
            return try deepSkyWindows(input, catalog: catalog)
        default:
            throw DeepSkyObservationInputError(capability)
        }
    }

    private static func horizontalPosition(_ input: [String: Any]) throws -> [String: Any] {
        let invalid = DeepSkyObservationInputError(horizontalPositionID)
        guard Set(input.keys) == ["right_ascension", "declination", "latitude", "longitude", "time"] else {
            throw invalid
        }
        let position = HorizontalCoordinates.position(
            rightAscensionHours: try number(input["right_ascension"], invalid),
            declinationDegrees: try number(input["declination"], invalid),
            latitudeDegrees: try number(input["latitude"], invalid),
            longitudeDegrees: try number(input["longitude"], invalid),
            at: try date(input["time"], invalid)
        )
        return ["altitude": position.altitude, "azimuth": position.azimuth]
    }

    private static func deepSkyWindows(
        _ input: [String: Any],
        catalog: [DeepSkyCatalogEntry]
    ) throws -> [String: Any] {
        let invalid = DeepSkyObservationInputError(deepSkyWindowsID)
        let allowed: Set<String> = [
            "target_id", "right_ascension", "declination", "latitude", "longitude",
            "night_start", "night_end", "minimum_altitude", "sample_interval_seconds",
        ]
        guard Set(input.keys).isSubset(of: allowed),
              Set(input.keys).isSuperset(of: ["latitude", "longitude", "night_start", "night_end"]) else {
            throw invalid
        }

        let rightAscension: Double
        let declination: Double
        let hasCoordinates = input["right_ascension"] != nil || input["declination"] != nil
        if let rawID = input["target_id"] {
            guard !hasCoordinates, let identifier = rawID as? String,
                  let entry = catalog.first(where: { $0.id == identifier }) else { throw invalid }
            rightAscension = entry.rightAscension
            declination = entry.declination
        } else {
            guard input["right_ascension"] != nil, input["declination"] != nil else { throw invalid }
            rightAscension = try number(input["right_ascension"], invalid)
            declination = try number(input["declination"], invalid)
        }

        let minimumAltitude = try input["minimum_altitude"].map { try number($0, invalid) }
            ?? DeepSkyObservation.defaultMinimumAltitude
        let sampleInterval = try input["sample_interval_seconds"].map { try number($0, invalid) }
            ?? DeepSkyObservation.defaultSampleInterval
        guard sampleInterval > 0 else { throw invalid }

        let start = try date(input["night_start"], invalid)
        let end = try date(input["night_end"], invalid)
        guard !exceedsSampleCap(start: start, end: end, sampleInterval: sampleInterval) else {
            throw DeepSkyObservationInputError(sampleCap: deepSkyWindowsID, maximum: maxSampleCount)
        }
        let windows = DeepSkyObservation.observe(
            rightAscensionHours: rightAscension,
            declinationDegrees: declination,
            latitudeDegrees: try number(input["latitude"], invalid),
            longitudeDegrees: try number(input["longitude"], invalid),
            start: start,
            end: end,
            minimumAltitude: minimumAltitude,
            sampleInterval: sampleInterval
        )
        return ["windows": try windows.map { window -> [String: Any] in
            [
                "start": try flooredTimestamp(window.start, invalid),
                "end": try flooredTimestamp(window.end, invalid),
                "best_time": try flooredTimestamp(window.bestTime, invalid),
                "max_altitude": window.maxAltitude,
                "azimuth": window.azimuth,
                "direction": window.direction,
            ]
        }]
    }

    private static func number(_ value: Any?, _ invalid: DeepSkyObservationInputError) throws -> Double {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else { throw invalid }
        return number.doubleValue
    }

    private static func formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    private static func date(_ value: Any?, _ invalid: DeepSkyObservationInputError) throws -> Date {
        guard let text = value as? String,
              text.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"#, options: .regularExpression) != nil,
              let date = formatter().date(from: text), formatter().string(from: date) == text,
              date >= earliestInstant, date <= latestInstant else {
            throw invalid
        }
        return date
    }

    /// Floor the epoch second toward negative infinity, then re-validate through
    /// `date` so the supported range is enforced on output as well as input.
    /// Window endpoints lie inside the injected interval, so an in-range request
    /// cannot produce an out-of-range instant.
    private static func flooredTimestamp(
        _ value: Date,
        _ invalid: DeepSkyObservationInputError
    ) throws -> String {
        let seconds = (value.timeIntervalSince1970).rounded(.down)
        guard seconds.isFinite else { throw invalid }
        let text = formatter().string(from: Date(timeIntervalSince1970: seconds))
        _ = try date(text, invalid)
        return text
    }
}

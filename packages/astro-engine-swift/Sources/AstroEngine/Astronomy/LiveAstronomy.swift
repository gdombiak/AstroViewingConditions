import Foundation
import CoreFoundation

/// Objective sampling shared with Apple hosts. Presentation and fallback stay with callers.
public struct MoonFacts: Sendable {
    public let illumination: MoonIlluminationSample
    public let position: MoonHorizontalCoordinates
}

public extension MoonSampling {
    func facts(latitude: Double, longitude: Double, at time: Date) throws -> MoonFacts {
        let illumination = try illumination(at: time)
        let position = try position(latitude: latitude, longitude: longitude, at: time)
        return MoonFacts(illumination: illumination, position: position)
    }
}

public struct SunEventSamples: Sendable {
    public let visual: SampledRiseSet
    public let civil: SampledRiseSet
    public let nautical: SampledRiseSet
    public let astronomical: SampledRiseSet

    public static func sample(latitude: Double, longitude: Double, on start: Date,
                              duration: TimeInterval? = nil,
                              sampler: any SunEventsSampling = SunCalcSunEventsSampler()) throws -> Self {
        func times(_ kind: SunTwilightKind) throws -> SampledRiseSet {
            if let duration {
                return try sampler.sunTimes(latitude: latitude, longitude: longitude,
                                            on: start, twilight: kind, duration: duration)
            }
            return try sampler.sunTimes(latitude: latitude, longitude: longitude, on: start, twilight: kind)
        }
        return try Self(visual: times(.visual), civil: times(.civil),
                        nautical: times(.nautical), astronomical: times(.astronomical))
    }
}

public struct AstronomyInputError: Error, Sendable {
    public let message: String
}

/// Portable JSON contract. No host calendar, approximation, provider or scoring calls.
public enum LiveAstronomy {
    public static func evaluate(_ capability: String, input: [String: Any],
                                moonSampler: any MoonSampling = SunCalcMoonSampler(timeZone: TimeZone(secondsFromGMT: 0)!),
                                sunSampler: any SunEventsSampling = SunCalcSunEventsSampler()) throws -> [String: Any] {
        let extra: Set<String>
        switch capability {
        case "astronomy.sun_events": extra = ["start", "end"]
        case "astronomy.moon_info": extra = ["time"]
        case "astronomy.moon_series": extra = ["times"]
        default: throw invalid("unknown astronomy capability")
        }
        guard Set(input.keys) == extra.union(["latitude", "longitude"]) else {
            throw invalid("missing or unknown astronomy input keys")
        }
        let latitude = try number(input["latitude"]), longitude = try number(input["longitude"])
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw invalid("coordinates out of range")
        }
        func moon(_ time: Date) throws -> [String: Any] {
            let facts = try moonSampler.facts(latitude: latitude, longitude: longitude, at: time)
            return ["time": utc(time), "altitude": facts.position.altitude,
                    "illumination": facts.illumination.illuminationPercent]
        }
        switch capability {
        case "astronomy.sun_events":
            let start = try instant(input["start"]), end = try instant(input["end"])
            let duration = end.timeIntervalSince(start)
            guard duration > 0, duration <= 26 * 3600 else { throw invalid("sun interval must be 0...26 hours, nonempty") }
            let samples = try SunEventSamples.sample(latitude: latitude, longitude: longitude,
                                                    on: start, duration: duration, sampler: sunSampler)
            func event(_ date: Date?) -> Any {
                guard let date, date >= start, date < end else { return NSNull() }
                return utc(date)
            }
            return ["start": utc(start), "end": utc(end),
                    "sunrise": event(samples.visual.rise), "sunset": event(samples.visual.set),
                    "civil_twilight_begin": event(samples.civil.rise), "civil_twilight_end": event(samples.civil.set),
                    "nautical_twilight_begin": event(samples.nautical.rise), "nautical_twilight_end": event(samples.nautical.set),
                    "astronomical_twilight_begin": event(samples.astronomical.rise),
                    "astronomical_twilight_end": event(samples.astronomical.set),
                    "astronomical_night_start": event(samples.astronomical.set),
                    "astronomical_night_end": event(samples.astronomical.rise)]
        case "astronomy.moon_info": return try moon(instant(input["time"]))
        default:
            guard let raw = input["times"] as? [Any], raw.count <= 49 else { throw invalid("times must contain at most 49 instants") }
            let times = try raw.map(instant)
            for (a, b) in zip(times, times.dropFirst()) where a >= b { throw invalid("times must increase strictly") }
            if let first = times.first, let last = times.last, last.timeIntervalSince(first) > 48 * 3600 {
                throw invalid("moon series spans more than 48 hours")
            }
            return ["samples": try times.map(moon)]
        }
    }

    public static func utc(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: floor(date.timeIntervalSince1970)))
    }

    private static func instant(_ raw: Any?) throws -> Date {
        guard let text = raw as? String, text.utf8.count == 20,
              text.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"#, options: .regularExpression) != nil,
              let date = ISO8601DateFormatter().date(from: text), utc(date) == text,
              text >= "2000-01-01T00:00:00Z", text < "2050-01-01T00:00:00Z" else {
            throw invalid("expected whole-second UTC instant in 2000...2049")
        }
        return date
    }
    private static func number(_ raw: Any?) throws -> Double {
        guard let n = raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else {
            throw invalid("expected finite coordinate number")
        }
        return n.doubleValue
    }
    private static func invalid(_ message: String) -> AstronomyInputError { AstronomyInputError(message: message) }
}

import Foundation
import SunCalc

// MARK: - DateTime adapter (SunCalc-only)

extension DateTime {
    var date: Date {
        Date(timeIntervalSince1970: timeIntervalSince1970)
    }
}

// MARK: - Moon samples

/// Instantaneous moon illumination used by live astronomy hosts.
public struct MoonIlluminationSample: Sendable, Hashable {
    /// Illuminated fraction in 0...1.
    public let fraction: Double
    /// Phase in degrees in the SunCalc range -180...180.
    public let phaseDegrees: Double

    public init(fraction: Double, phaseDegrees: Double) {
        self.fraction = fraction
        self.phaseDegrees = phaseDegrees
    }

    public var illuminationPercent: Int {
        Int(fraction * 100)
    }
}

/// Instantaneous moon horizontal coordinates.
public struct MoonHorizontalCoordinates: Sendable, Hashable {
    public let altitude: Double
    public let azimuth: Double

    public init(altitude: Double, azimuth: Double) {
        self.altitude = altitude
        self.azimuth = azimuth
    }
}

/// Time-stamped moon position sample used by moon observation.
public struct MoonPositionSample: Sendable, Hashable {
    public let time: Date
    public let altitude: Double
    public let azimuth: Double?

    public init(time: Date, altitude: Double, azimuth: Double?) {
        self.time = time
        self.altitude = altitude
        self.azimuth = azimuth
    }
}

/// Injected 1:1 moon series row for deterministic night-conditions analysis.
public struct MoonSample: Sendable, Hashable {
    public let time: Date
    public let altitudeDegrees: Double
    public let illuminationPercent: Int

    public init(time: Date, altitudeDegrees: Double, illuminationPercent: Int) {
        self.time = time
        self.altitudeDegrees = altitudeDegrees
        self.illuminationPercent = illuminationPercent
    }
}

public struct SampledMoonTimes: Sendable, Hashable {
    public let rise: Date?
    public let set: Date?
    public let alwaysUp: Bool
    public let alwaysDown: Bool

    public init(rise: Date?, set: Date?, alwaysUp: Bool, alwaysDown: Bool) {
        self.rise = rise
        self.set = set
        self.alwaysUp = alwaysUp
        self.alwaysDown = alwaysDown
    }
}

public protocol MoonSampling: Sendable {
    func illumination(at time: Date) throws -> MoonIlluminationSample
    func position(latitude: Double, longitude: Double, at time: Date) throws -> MoonHorizontalCoordinates
}

public protocol MoonTimesSampling: Sendable {
    func moonTimes(
        latitude: Double,
        longitude: Double,
        on start: Date,
        duration: TimeInterval
    ) throws -> SampledMoonTimes
}

// MARK: - Sun events samples

public enum SunTwilightKind: Sendable, Hashable {
    case visual
    case civil
    case nautical
    case astronomical
}

public struct SampledRiseSet: Sendable, Hashable {
    public let rise: Date?
    public let set: Date?

    public init(rise: Date?, set: Date?) {
        self.rise = rise
        self.set = set
    }
}

public protocol SunEventsSampling: Sendable {
    func sunTimes(
        latitude: Double,
        longitude: Double,
        on date: Date,
        twilight: SunTwilightKind
    ) throws -> SampledRiseSet
}

// MARK: - SunCalc-backed implementations

public struct SunCalcMoonSampler: MoonSampling {
    public init() {}

    public func illumination(at time: Date) throws -> MoonIlluminationSample {
        let illumination = try MoonIllumination.compute()
            .on(time)
            .execute()
        return MoonIlluminationSample(fraction: illumination.fraction, phaseDegrees: illumination.phase)
    }

    public func position(
        latitude: Double,
        longitude: Double,
        at time: Date
    ) throws -> MoonHorizontalCoordinates {
        let position = try MoonPosition.compute()
            .at(latitude, longitude)
            .on(time)
            .execute()
        return MoonHorizontalCoordinates(altitude: position.altitude, azimuth: position.azimuth)
    }
}

public struct SunCalcMoonTimesSampler: MoonTimesSampling {
    public init() {}

    public func moonTimes(
        latitude: Double,
        longitude: Double,
        on start: Date,
        duration: TimeInterval
    ) throws -> SampledMoonTimes {
        let times = try MoonTimes.compute()
            .at(latitude, longitude)
            .on(start)
            .limit(duration)
            .execute()
        return SampledMoonTimes(
            rise: times.rise?.date,
            set: times.set?.date,
            alwaysUp: times.alwaysUp,
            alwaysDown: times.alwaysDown
        )
    }
}

public struct SunCalcSunEventsSampler: SunEventsSampling {
    public init() {}

    public func sunTimes(
        latitude: Double,
        longitude: Double,
        on date: Date,
        twilight: SunTwilightKind
    ) throws -> SampledRiseSet {
        let times = try SunTimes.compute()
            .at(latitude, longitude)
            .on(date)
            .twilight(twilight.sunCalcTwilight)
            .execute()
        return SampledRiseSet(rise: times.rise?.date, set: times.set?.date)
    }
}

private extension SunTwilightKind {
    var sunCalcTwilight: Twilight {
        switch self {
        case .visual: return .visual
        case .civil: return .civil
        case .nautical: return .nautical
        case .astronomical: return .astronomical
        }
    }
}

import Foundation

public struct MoonObservationData: Sendable, Hashable {
    public let phase: Double
    public let phaseName: String
    public let illumination: Int
    public let rise: Date?
    public let set: Date?
    public let alwaysUp: Bool
    public let alwaysDown: Bool
    public let positionSamples: [MoonPositionSample]

    public init(
        phase: Double,
        phaseName: String,
        illumination: Int,
        rise: Date?,
        set: Date?,
        alwaysUp: Bool,
        alwaysDown: Bool,
        positionSamples: [MoonPositionSample]
    ) {
        self.phase = min(max(phase, 0), 1)
        self.phaseName = phaseName
        self.illumination = min(max(illumination, 0), 100)
        self.rise = rise
        self.set = set
        self.alwaysUp = alwaysUp
        self.alwaysDown = alwaysDown
        self.positionSamples = positionSamples
    }
}

/// SunCalc-backed moon observation without host recommendation types.
///
/// Portable contract: contracts/procedures/moon-observation.md. The default
/// 1800 s cadence, the explicit interval-end sample, the night-midpoint phase
/// instant and the `max(span, sampleInterval)` rise/set search limit are the
/// production quirks and are preserved deliberately.
public struct SunCalcMoonObservationSampler: Sendable {
    /// Production cadence of `SunCalcMoonAstronomyProvider`.
    public static let defaultSampleInterval: TimeInterval = 30 * 60

    private let sampleInterval: TimeInterval
    private let moonSampler: SunCalcMoonSampler
    private let moonTimesSampler: SunCalcMoonTimesSampler

    public init(sampleInterval: TimeInterval = SunCalcMoonObservationSampler.defaultSampleInterval,
                timeZone: TimeZone? = nil) {
        self.sampleInterval = sampleInterval
        self.moonSampler = SunCalcMoonSampler(timeZone: timeZone)
        self.moonTimesSampler = SunCalcMoonTimesSampler()
    }

    /// Host entry point. A midpoint sampling failure degrades to `fallback`,
    /// preserving the existing iOS behavior.
    public func observation(
        latitude: Double,
        longitude: Double,
        nightStart: Date,
        nightEnd: Date,
        fallback: MoonInfo
    ) -> MoonObservationData {
        let midpoint = midpoint(nightStart: nightStart, nightEnd: nightEnd)
        let moonInfo: MoonInfo
        do {
            moonInfo = try calculateMoonInfo(
                latitude: latitude,
                longitude: longitude,
                on: midpoint,
                emoji: fallback.emoji
            )
        } catch {
            moonInfo = fallback
        }
        return assemble(
            latitude: latitude,
            longitude: longitude,
            nightStart: nightStart,
            nightEnd: nightEnd,
            moonInfo: moonInfo
        )
    }

    /// Portable entry point. There is no host fallback DTO in the transport, so
    /// a midpoint sampling failure is an engine failure rather than silent data.
    public func observation(
        latitude: Double,
        longitude: Double,
        nightStart: Date,
        nightEnd: Date
    ) throws -> MoonObservationData {
        let moonInfo = try calculateMoonInfo(
            latitude: latitude,
            longitude: longitude,
            on: midpoint(nightStart: nightStart, nightEnd: nightEnd),
            emoji: ""
        )
        return assemble(
            latitude: latitude,
            longitude: longitude,
            nightStart: nightStart,
            nightEnd: nightEnd,
            moonInfo: moonInfo
        )
    }

    /// `max(span, 0) / 2` past the start: an inverted interval samples the start.
    private func midpoint(nightStart: Date, nightEnd: Date) -> Date {
        nightStart.addingTimeInterval(max(nightEnd.timeIntervalSince(nightStart), 0) / 2)
    }

    private func assemble(
        latitude: Double,
        longitude: Double,
        nightStart: Date,
        nightEnd: Date,
        moonInfo: MoonInfo
    ) -> MoonObservationData {
        let moonTimes = calculateMoonTimes(
            latitude: latitude,
            longitude: longitude,
            start: nightStart,
            duration: max(nightEnd.timeIntervalSince(nightStart), sampleInterval)
        )
        let samples = calculatePositionSamples(
            latitude: latitude,
            longitude: longitude,
            start: nightStart,
            end: nightEnd
        )

        return MoonObservationData(
            phase: moonInfo.phase,
            phaseName: moonInfo.phaseName,
            illumination: moonInfo.illumination,
            rise: moonTimes.rise,
            set: moonTimes.set,
            alwaysUp: moonTimes.alwaysUp,
            alwaysDown: moonTimes.alwaysDown,
            positionSamples: samples
        )
    }

    private func calculateMoonInfo(
        latitude: Double,
        longitude: Double,
        on date: Date,
        emoji: String
    ) throws -> MoonInfo {
        let facts = try moonSampler.facts(latitude: latitude, longitude: longitude, at: date)
        let illumination = facts.illumination
        let position = facts.position
        let phase = normalizePhase(illumination.phaseDegrees)
        return MoonInfo(
            phase: phase,
            phaseName: phaseName(for: phase),
            altitude: position.altitude,
            illumination: illumination.illuminationPercent,
            emoji: emoji
        )
    }

    private func calculateMoonTimes(
        latitude: Double,
        longitude: Double,
        start: Date,
        duration: TimeInterval
    ) -> SampledMoonTimes {
        do {
            return try moonTimesSampler.moonTimes(
                latitude: latitude,
                longitude: longitude,
                on: start,
                duration: duration
            )
        } catch {
            return SampledMoonTimes(rise: nil, set: nil, alwaysUp: false, alwaysDown: false)
        }
    }

    private func calculatePositionSamples(
        latitude: Double,
        longitude: Double,
        start: Date,
        end: Date
    ) -> [MoonPositionSample] {
        guard end >= start else { return [] }

        var samples: [MoonPositionSample] = []
        var time = start

        while time <= end {
            if let sample = calculatePositionSample(latitude: latitude, longitude: longitude, at: time) {
                samples.append(sample)
            }
            time = time.addingTimeInterval(sampleInterval)
        }

        if samples.last?.time != end,
           let endSample = calculatePositionSample(latitude: latitude, longitude: longitude, at: end) {
            samples.append(endSample)
        }

        return samples
    }

    private func calculatePositionSample(
        latitude: Double,
        longitude: Double,
        at time: Date
    ) -> MoonPositionSample? {
        do {
            let position = try moonSampler.position(latitude: latitude, longitude: longitude, at: time)
            return MoonPositionSample(time: time, altitude: position.altitude, azimuth: position.azimuth)
        } catch {
            return nil
        }
    }

    private func normalizePhase(_ phase: Double) -> Double {
        (phase + 180) / 360
    }

    private func phaseName(for phase: Double) -> String {
        switch phase {
        case 0..<0.05, 0.95...1:
            return "New Moon"
        case 0.05..<0.20:
            return "Waxing Crescent"
        case 0.20..<0.30:
            return "First Quarter"
        case 0.30..<0.45:
            return "Waxing Gibbous"
        case 0.45..<0.55:
            return "Full Moon"
        case 0.55..<0.70:
            return "Waning Gibbous"
        case 0.70..<0.80:
            return "Last Quarter"
        default:
            return "Waning Crescent"
        }
    }
}

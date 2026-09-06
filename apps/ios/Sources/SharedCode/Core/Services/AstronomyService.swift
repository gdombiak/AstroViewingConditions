import Foundation
import os
import AstroEngine

private let astronomyLogger = Logger(subsystem: "com.astroviewing.conditions", category: "AstronomyService")

public protocol AstronomyProviding: Sendable {
    func calculateSunEvents(latitude: Double, longitude: Double, on date: Date) async -> SunEvents
    func calculateMoonInfo(latitude: Double, longitude: Double, on date: Date) async -> MoonInfo
}

public actor AstronomyService: AstronomyProviding {
    private let sunEventsSampler: any SunEventsSampling
    private let moonSampler: any MoonSampling

    public init(
        sunEventsSampler: any SunEventsSampling = SunCalcSunEventsSampler(),
        moonSampler: any MoonSampling = SunCalcMoonSampler()
    ) {
        self.sunEventsSampler = sunEventsSampler
        self.moonSampler = moonSampler
    }

    public func calculateSunEvents(
        latitude: Double,
        longitude: Double,
        on date: Date
    ) -> SunEvents {
        do {
            let visualTimes = try sunEventsSampler.sunTimes(
                latitude: latitude, longitude: longitude, on: date, twilight: .visual
            )
            let civilTimes = try sunEventsSampler.sunTimes(
                latitude: latitude, longitude: longitude, on: date, twilight: .civil
            )
            let nauticalTimes = try sunEventsSampler.sunTimes(
                latitude: latitude, longitude: longitude, on: date, twilight: .nautical
            )
            let astronomicalTimes = try sunEventsSampler.sunTimes(
                latitude: latitude, longitude: longitude, on: date, twilight: .astronomical
            )

            let fallback = approximateSunEvents(on: date)
            let hasMissingTimes = [
                visualTimes.rise,
                visualTimes.set,
                civilTimes.rise,
                civilTimes.set,
                nauticalTimes.rise,
                nauticalTimes.set,
                astronomicalTimes.rise,
                astronomicalTimes.set
            ].contains { $0 == nil }

            if hasMissingTimes {
                astronomyLogger.warning("Sun calculation returned missing times for latitude \(latitude), longitude \(longitude); using approximate fallback values for missing events")
            }

            return SunEvents(
                sunrise: visualTimes.rise ?? fallback.sunrise,
                sunset: visualTimes.set ?? fallback.sunset,
                civilTwilightBegin: civilTimes.rise ?? fallback.civilTwilightBegin,
                civilTwilightEnd: civilTimes.set ?? fallback.civilTwilightEnd,
                nauticalTwilightBegin: nauticalTimes.rise ?? fallback.nauticalTwilightBegin,
                nauticalTwilightEnd: nauticalTimes.set ?? fallback.nauticalTwilightEnd,
                astronomicalTwilightBegin: astronomicalTimes.rise ?? fallback.astronomicalTwilightBegin,
                astronomicalTwilightEnd: astronomicalTimes.set ?? fallback.astronomicalTwilightEnd
            )
        } catch {
            astronomyLogger.error("Failed to calculate sun events for latitude \(latitude), longitude \(longitude): \(error.localizedDescription)")
            return approximateSunEvents(on: date)
        }
    }

    public func calculateMoonInfo(
        latitude: Double,
        longitude: Double,
        on date: Date
    ) -> MoonInfo {
        do {
            let illumination = try moonSampler.illumination(at: date)
            let position = try moonSampler.position(latitude: latitude, longitude: longitude, at: date)
            let phase = illumination.phaseDegrees
            let phaseName = getMoonPhaseName(phase: phase)
            let emoji = getMoonEmoji(phase: phase)

            return MoonInfo(
                phase: normalizePhase(phase),
                phaseName: phaseName,
                altitude: position.altitude,
                illumination: illumination.illuminationPercent,
                emoji: emoji
            )
        } catch {
            astronomyLogger.error("Failed to calculate moon info for latitude \(latitude), longitude \(longitude): \(error.localizedDescription)")
            return MoonInfo(
                phase: 0.5,
                phaseName: "Unknown",
                altitude: 0,
                illumination: 0,
                emoji: "🌙"
            )
        }
    }

    public func calculateMoonAltitude(
        latitude: Double,
        longitude: Double,
        at time: Date
    ) -> Double {
        do {
            return try moonSampler.position(latitude: latitude, longitude: longitude, at: time).altitude
        } catch {
            astronomyLogger.error("Failed to calculate moon altitude for latitude \(latitude), longitude \(longitude): \(error.localizedDescription)")
            return 0
        }
    }

    private func normalizePhase(_ phase: Double) -> Double {
        let normalized = (phase + 180) / 360
        return normalized
    }

    /// Foundation-only polar/missing-time fallback. Not part of SunCalc sampling.
    private func approximateSunEvents(on date: Date) -> SunEvents {
        SunEvents(
            sunrise: date.addingTimeInterval(6 * 3600),
            sunset: date.addingTimeInterval(18 * 3600),
            civilTwilightBegin: date.addingTimeInterval(5 * 3600),
            civilTwilightEnd: date.addingTimeInterval(19 * 3600),
            nauticalTwilightBegin: date.addingTimeInterval(4.5 * 3600),
            nauticalTwilightEnd: date.addingTimeInterval(19.5 * 3600),
            astronomicalTwilightBegin: date.addingTimeInterval(4 * 3600),
            astronomicalTwilightEnd: date.addingTimeInterval(20 * 3600)
        )
    }

    private func getMoonPhaseName(phase: Double) -> String {
        switch phase {
        case -10...10:
            return "Full Moon"
        case 10..<80:
            return "Waning Gibbous"
        case 80...100:
            return "Last Quarter"
        case 100..<170:
            return "Waning Crescent"
        case ...(-170), 170...:
            return "New Moon"
        case -170..<(-100):
            return "Waxing Crescent"
        case -100...(-80):
            return "First Quarter"
        case -80..<(-10):
            return "Waxing Gibbous"
        default:
            return "Unknown"
        }
    }

    private func getMoonEmoji(phase: Double) -> String {
        switch phase {
        case -10...10:
            return "🌕"
        case 10..<80:
            return "🌖"
        case 80...100:
            return "🌗"
        case 100..<170:
            return "🌘"
        case ...(-170), 170...:
            return "🌑"
        case -170..<(-100):
            return "🌒"
        case -100...(-80):
            return "🌓"
        case -80..<(-10):
            return "🌔"
        default:
            return "🌙"
        }
    }
}

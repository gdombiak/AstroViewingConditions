import Foundation
import os
import SunCalc

private let astronomyLogger = Logger(subsystem: "com.astroviewing.conditions", category: "AstronomyService")

public actor AstronomyService {
    public init() {}
    
    public func calculateSunEvents(
        latitude: Double,
        longitude: Double,
        on date: Date
    ) -> SunEvents {
        do {
            // Visual sunrise/sunset
            let visualTimes = try SunTimes.compute()
                .at(latitude, longitude)
                .on(date)
                .twilight(Twilight.visual)
                .execute()
            
            // Civil twilight
            let civilTimes = try SunTimes.compute()
                .at(latitude, longitude)
                .on(date)
                .twilight(Twilight.civil)
                .execute()
            
            // Nautical twilight
            let nauticalTimes = try SunTimes.compute()
                .at(latitude, longitude)
                .on(date)
                .twilight(Twilight.nautical)
                .execute()
            
            // Astronomical twilight
            let astronomicalTimes = try SunTimes.compute()
                .at(latitude, longitude)
                .on(date)
                .twilight(Twilight.astronomical)
                .execute()
            
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
                sunrise: visualTimes.rise?.date ?? fallback.sunrise,
                sunset: visualTimes.set?.date ?? fallback.sunset,
                civilTwilightBegin: civilTimes.rise?.date ?? fallback.civilTwilightBegin,
                civilTwilightEnd: civilTimes.set?.date ?? fallback.civilTwilightEnd,
                nauticalTwilightBegin: nauticalTimes.rise?.date ?? fallback.nauticalTwilightBegin,
                nauticalTwilightEnd: nauticalTimes.set?.date ?? fallback.nauticalTwilightEnd,
                astronomicalTwilightBegin: astronomicalTimes.rise?.date ?? fallback.astronomicalTwilightBegin,
                astronomicalTwilightEnd: astronomicalTimes.set?.date ?? fallback.astronomicalTwilightEnd
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
            // Moon illumination
            let illumination = try MoonIllumination.compute()
                .on(date)
                .execute()
            
            // Moon position
            let position = try MoonPosition.compute()
                .at(latitude, longitude)
                .on(date)
                .execute()
            
            let phase = illumination.phase
            let phaseName = getMoonPhaseName(phase: phase)
            let emoji = getMoonEmoji(phase: phase)
            
            return MoonInfo(
                phase: normalizePhase(phase),
                phaseName: phaseName,
                altitude: position.altitude,
                illumination: Int(illumination.fraction * 100),
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
            let position = try MoonPosition.compute()
                .at(latitude, longitude)
                .on(time)
                .execute()
            return position.altitude
        } catch {
            astronomyLogger.error("Failed to calculate moon altitude for latitude \(latitude), longitude \(longitude): \(error.localizedDescription)")
            return 0
        }
    }
    
    // MARK: - Helper Methods
    
    private func normalizePhase(_ phase: Double) -> Double {
        // Convert phase from degrees (-180 to 180) to 0-1 range
        let normalized = (phase + 180) / 360
        return normalized
    }

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
        // Phase is in degrees (-180 to 180)
        // -180° → 0°: Waxing (New Moon → Full Moon)
        // 0° → 180°: Waning (Full Moon → New Moon)
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
        // Phase is in degrees (-180 to 180)
        // -180° → 0°: Waxing (New Moon → Full Moon)
        // 0° → 180°: Waning (Full Moon → New Moon)
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

// MARK: - DateTime Extension

extension DateTime {
    var date: Date {
        return Date(timeIntervalSince1970: timeIntervalSince1970)
    }
}

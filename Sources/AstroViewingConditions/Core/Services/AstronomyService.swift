import Foundation
import SunCalc

public actor AstronomyService {
    public init() {}
    
    public func calculateSunEvents(
        for location: SavedLocation,
        on date: Date
    ) -> SunEvents {
        do {
            // Visual sunrise/sunset
            let visualTimes = try SunTimes.compute()
                .at(location.latitude, location.longitude)
                .on(date)
                .twilight(Twilight.visual)
                .execute()
            
            // Civil twilight
            let civilTimes = try SunTimes.compute()
                .at(location.latitude, location.longitude)
                .on(date)
                .twilight(Twilight.civil)
                .execute()
            
            // Nautical twilight
            let nauticalTimes = try SunTimes.compute()
                .at(location.latitude, location.longitude)
                .on(date)
                .twilight(Twilight.nautical)
                .execute()
            
            // Astronomical twilight
            let astronomicalTimes = try SunTimes.compute()
                .at(location.latitude, location.longitude)
                .on(date)
                .twilight(Twilight.astronomical)
                .execute()
            
            return SunEvents(
                sunrise: visualTimes.rise?.date ?? date,
                sunset: visualTimes.set?.date ?? date,
                civilTwilightBegin: civilTimes.rise?.date ?? date,
                civilTwilightEnd: civilTimes.set?.date ?? date,
                nauticalTwilightBegin: nauticalTimes.rise?.date ?? date,
                nauticalTwilightEnd: nauticalTimes.set?.date ?? date,
                astronomicalTwilightBegin: astronomicalTimes.rise?.date ?? date,
                astronomicalTwilightEnd: astronomicalTimes.set?.date ?? date
            )
        } catch {
            print("Error calculating sun events: \(error)")
            // Return default values if calculation fails
            return SunEvents(
                sunrise: date,
                sunset: date,
                civilTwilightBegin: date,
                civilTwilightEnd: date,
                nauticalTwilightBegin: date,
                nauticalTwilightEnd: date,
                astronomicalTwilightBegin: date,
                astronomicalTwilightEnd: date
            )
        }
    }
    
    public func calculateMoonInfo(
        for location: SavedLocation,
        on date: Date
    ) -> MoonInfo {
        do {
            // Moon illumination
            let illumination = try MoonIllumination.compute()
                .on(date)
                .execute()
            
            // Moon position
            let position = try MoonPosition.compute()
                .at(location.latitude, location.longitude)
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
            print("Error calculating moon info: \(error)")
            return MoonInfo(
                phase: 0.5,
                phaseName: "Unknown",
                altitude: 0,
                illumination: 0,
                emoji: "🌙"
            )
        }
    }
    
    // MARK: - Helper Methods
    
    private func normalizePhase(_ phase: Double) -> Double {
        // Convert phase from degrees (-180 to 180) to 0-1 range
        let normalized = (phase + 180) / 360
        return normalized
    }
    
    private func getMoonPhaseName(phase: Double) -> String {
        // Phase is in degrees (-180 to 180)
        switch phase {
        case -10...10:
            return "New Moon"
        case 10..<80:
            return "Waxing Crescent"
        case 80...100:
            return "First Quarter"
        case 100..<170:
            return "Waxing Gibbous"
        case ...(-170), 170...:
            return "Full Moon"
        case -170..<(-100):
            return "Waning Gibbous"
        case -100...(-80):
            return "Last Quarter"
        case -80..<(-10):
            return "Waning Crescent"
        default:
            return "Unknown"
        }
    }
    
    private func getMoonEmoji(phase: Double) -> String {
        // Phase is in degrees (-180 to 180)
        switch phase {
        case -10...10:
            return "🌑"
        case 10..<80:
            return "🌒"
        case 80...100:
            return "🌓"
        case 100..<170:
            return "🌔"
        case ...(-170), 170...:
            return "🌕"
        case -170..<(-100):
            return "🌖"
        case -100...(-80):
            return "🌗"
        case -80..<(-10):
            return "🌘"
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

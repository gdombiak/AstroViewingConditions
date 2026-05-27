import Foundation

public struct NightForecastFilter: Sendable {
    
    public static func calculateNightRange(
        sunEventsToday: SunEvents,
        sunEventsTomorrow: SunEvents?,
        for date: Date,
        calendar: Calendar
    ) -> (start: Date, end: Date) {
        let startOfDay = calendar.startOfDay(for: date)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let duskHour = calendar.component(.hour, from: sunEventsToday.astronomicalTwilightEnd)
        let duskMinute = calendar.component(.minute, from: sunEventsToday.astronomicalTwilightEnd)
        let nightStart = calendar.date(bySettingHour: duskHour, minute: duskMinute, second: 0, of: startOfDay)!
        
        let tomorrowSunEvents = sunEventsTomorrow ?? sunEventsToday
        let dawnHour = calendar.component(.hour, from: tomorrowSunEvents.astronomicalTwilightBegin)
        let dawnMinute = calendar.component(.minute, from: tomorrowSunEvents.astronomicalTwilightBegin)
        let nightEnd = calendar.date(bySettingHour: dawnHour, minute: dawnMinute, second: 0, of: nextDay)!
        
        return (nightStart, nightEnd)
    }
    
    public static func filterToNighttime(
        forecasts: [HourlyForecast],
        sunEventsToday: SunEvents,
        sunEventsTomorrow: SunEvents?,
        for date: Date,
        calendar: Calendar
    ) -> [HourlyForecast] {
        let (nightStart, nightEnd) = calculateNightRange(
            sunEventsToday: sunEventsToday,
            sunEventsTomorrow: sunEventsTomorrow,
            for: date,
            calendar: calendar
        )
        
        return forecasts.filter { forecast in
            forecast.time >= nightStart && forecast.time < nightEnd
        }
    }
}

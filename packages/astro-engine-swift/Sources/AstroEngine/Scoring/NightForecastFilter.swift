import Foundation

public struct NightForecastFilter: Sendable {
    
    public static func calculateNightRange(
        sunEventsToday: SunEvents,
        sunEventsTomorrow: SunEvents?,
        for date: Date,
        calendar: Calendar
    ) -> (start: Date, end: Date) {
        let window = NightForecastWindowDeriver.derive(
            sunEventsToday: sunEventsToday,
            sunEventsTomorrow: sunEventsTomorrow,
            for: date,
            calendar: calendar
        )
        return (window.start, window.end)
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

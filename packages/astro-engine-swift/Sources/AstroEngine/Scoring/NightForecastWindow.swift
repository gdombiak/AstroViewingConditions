import Foundation

/// The calendar-projected interval used to select hourly forecasts for one
/// observing night.
public struct NightForecastWindow: Sendable, Equatable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

/// Authoritative calendar/DST projection formerly embedded in
/// ``NightForecastFilter``.
///
/// The host supplies an observing-day instant, a Gregorian location calendar,
/// and already-computed Sun events. This type fetches nothing and resolves no
/// timezone. It intentionally preserves Foundation's `startOfDay`, day-addition
/// and wall-clock replacement behavior, including ambiguous and missing hours.
public enum NightForecastWindowDeriver {
    public static let capabilityID = "night_forecast.derive_window"

    public static func derive(
        astronomicalTwilightEnd: Date,
        astronomicalTwilightBegin: Date,
        tomorrowAstronomicalTwilightBegin: Date?,
        for date: Date,
        calendar: Calendar
    ) -> NightForecastWindow {
        let startOfDay = calendar.startOfDay(for: date)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)
            ?? startOfDay.addingTimeInterval(24 * 60 * 60)

        let duskHour = calendar.component(.hour, from: astronomicalTwilightEnd)
        let duskMinute = calendar.component(.minute, from: astronomicalTwilightEnd)
        let nightStart = calendar.date(
            bySettingHour: duskHour,
            minute: duskMinute,
            second: 0,
            of: startOfDay
        ) ?? astronomicalTwilightEnd

        let dawn = tomorrowAstronomicalTwilightBegin ?? astronomicalTwilightBegin
        let dawnHour = calendar.component(.hour, from: dawn)
        let dawnMinute = calendar.component(.minute, from: dawn)
        let nightEnd = calendar.date(
            bySettingHour: dawnHour,
            minute: dawnMinute,
            second: 0,
            of: nextDay
        ) ?? dawn

        return NightForecastWindow(start: nightStart, end: nightEnd)
    }

    public static func derive(
        sunEventsToday: SunEvents,
        sunEventsTomorrow: SunEvents?,
        for date: Date,
        calendar: Calendar
    ) -> NightForecastWindow {
        derive(
            astronomicalTwilightEnd: sunEventsToday.astronomicalTwilightEnd,
            astronomicalTwilightBegin: sunEventsToday.astronomicalTwilightBegin,
            tomorrowAstronomicalTwilightBegin: sunEventsTomorrow?.astronomicalTwilightBegin,
            for: date,
            calendar: calendar
        )
    }
}

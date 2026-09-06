import Foundation
import AstroEngine

extension NightQualityAnalyzer {
    public static func analyzeConditions(
        _ conditions: ViewingConditions,
        dayOffset: Int = 0,
        referenceDate: Date = Date()
    ) -> NightQualityAssessment? {
        guard let firstForecastTime = conditions.hourlyForecasts.first else { return nil }

        let timeZone = conditions.timeZoneIdentifier
            .flatMap(TimeZone.init(identifier:))
            ?? LocationTimeZoneResolver.approximate(longitude: conditions.location.longitude)
        let calendar = LocationTimeZoneResolver.calendar(for: timeZone)
        let firstForecastDay = calendar.startOfDay(for: firstForecastTime.time)
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let targetDay = calendar.date(byAdding: .day, value: dayOffset, to: referenceDay) ?? referenceDay
        let dayIndex = calendar.dateComponents([.day], from: firstForecastDay, to: targetDay).day ?? dayOffset

        guard dayIndex >= 0,
              dayIndex < conditions.dailySunEvents.count,
              dayIndex < conditions.dailyMoonInfo.count else {
            return nil
        }

        let startOfSelectedDay = calendar.date(byAdding: .day, value: dayIndex, to: firstForecastDay) ?? targetDay
        let endOfFollowingDay = calendar.date(byAdding: .day, value: 3, to: startOfSelectedDay) ?? startOfSelectedDay
        let forecasts = conditions.hourlyForecasts.filter { forecast in
            forecast.time >= startOfSelectedDay && forecast.time < endOfFollowingDay
        }

        let sunEventsToday = conditions.dailySunEvents[dayIndex]
        let sunEventsTomorrowIndex = dayIndex + 1
        let sunEventsTomorrow = sunEventsTomorrowIndex < conditions.dailySunEvents.count
            ? conditions.dailySunEvents[sunEventsTomorrowIndex]
            : nil
        let moonInfo = conditions.dailyMoonInfo[dayIndex]

        return analyzeNight(
            forecasts: forecasts,
            sunEventsToday: sunEventsToday,
            sunEventsTomorrow: sunEventsTomorrow,
            moonInfo: moonInfo,
            latitude: conditions.location.latitude,
            longitude: conditions.location.longitude,
            for: startOfSelectedDay,
            calendar: calendar
        )
    }
}

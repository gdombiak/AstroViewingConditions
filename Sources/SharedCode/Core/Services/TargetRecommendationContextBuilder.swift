import Foundation

public struct TargetRecommendationContextResolution: Sendable {
    public let context: TargetRecommendationContext
    public let observingDate: Date
    public let timeZone: TimeZone
    public let sunEventsToday: SunEvents

    public init(
        context: TargetRecommendationContext,
        observingDate: Date,
        timeZone: TimeZone,
        sunEventsToday: SunEvents
    ) {
        self.context = context
        self.observingDate = observingDate
        self.timeZone = timeZone
        self.sunEventsToday = sunEventsToday
    }
}

/// Resolves the existing recommendation inputs for a local observing date.
/// This type assembles domain inputs only; it does not generate, rank, filter,
/// or present recommendations.
public enum TargetRecommendationContextBuilder {
    public static func resolve(
        conditions: ViewingConditions,
        dayOffset: Int,
        referenceDate: Date = Date(),
        timeZone preferredTimeZone: TimeZone? = nil
    ) -> TargetRecommendationContextResolution? {
        let timeZone = preferredTimeZone
            ?? conditions.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? LocationTimeZoneResolver.approximate(longitude: conditions.location.longitude)
        let calendar = LocationTimeZoneResolver.calendar(for: timeZone)
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let dayIndex: Int
        if let firstForecastTime = conditions.hourlyForecasts.first?.time {
            let firstForecastDay = calendar.startOfDay(for: firstForecastTime)
            let elapsedDays = calendar.dateComponents(
                [.day],
                from: firstForecastDay,
                to: referenceDay
            ).day ?? 0
            dayIndex = elapsedDays + dayOffset
        } else {
            dayIndex = dayOffset
        }

        guard dayIndex >= 0,
              dayIndex < conditions.dailySunEvents.count,
              dayIndex < conditions.dailyMoonInfo.count,
              let observingDate = calendar.date(
                byAdding: .day,
                value: dayOffset,
                to: referenceDay
              ) else {
            return nil
        }

        let sunEventsToday = conditions.dailySunEvents[dayIndex]
        let nextIndex = dayIndex + 1
        let sunEventsTomorrow = nextIndex < conditions.dailySunEvents.count
            ? conditions.dailySunEvents[nextIndex]
            : nil
        let moonInfo = conditions.dailyMoonInfo[dayIndex]
        let endOfForecastRange = calendar.date(
            byAdding: .day,
            value: 3,
            to: observingDate
        ) ?? observingDate
        let forecasts = conditions.hourlyForecasts.filter {
            $0.time >= observingDate && $0.time < endOfForecastRange
        }
        let nightQuality = NightQualityAnalyzer.analyzeNight(
            forecasts: forecasts,
            sunEventsToday: sunEventsToday,
            sunEventsTomorrow: sunEventsTomorrow,
            moonInfo: moonInfo,
            latitude: conditions.location.latitude,
            longitude: conditions.location.longitude,
            for: observingDate,
            calendar: calendar
        )

        return TargetRecommendationContextResolution(
            context: TargetRecommendationContext(
                location: conditions.location,
                astronomicalNightStart: sunEventsToday.astronomicalNightStart,
                astronomicalNightEnd: sunEventsToday.astronomicalNightEnd(
                    using: sunEventsTomorrow
                ),
                nightQuality: nightQuality,
                moonInfo: moonInfo
            ),
            observingDate: observingDate,
            timeZone: timeZone,
            sunEventsToday: sunEventsToday
        )
    }
}

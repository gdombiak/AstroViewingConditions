import SharedCode
import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> NightConditionsEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @Sendable @escaping (NightConditionsEntry) -> Void) {
        Task { @Sendable in
            let entry = await buildEntry() ?? .placeholder
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @Sendable @escaping (Timeline<NightConditionsEntry>) -> Void) {
        Task { @Sendable in
            let entry = await buildEntry() ?? .placeholder
            let nextHour = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
            completion(Timeline(entries: [entry], policy: .after(nextHour)))
        }
    }

    private func buildEntry() async -> NightConditionsEntry? {
        guard let location = WidgetLocationStore.load() else { return nil }

        let weatherService = WeatherService()
        let astronomyService = AstronomyService()

        guard let forecasts = try? await weatherService.fetchForecast(
            latitude: location.latitude,
            longitude: location.longitude,
            days: 3
        ) else { return nil }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let sunEventsToday = await astronomyService.calculateSunEvents(
            latitude: location.latitude,
            longitude: location.longitude,
            on: today
        )
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let sunEventsTomorrow = await astronomyService.calculateSunEvents(
            latitude: location.latitude,
            longitude: location.longitude,
            on: tomorrow
        )
        let moonInfo = await astronomyService.calculateMoonInfo(
            latitude: location.latitude,
            longitude: location.longitude,
            on: today
        )

        let assessment = NightQualityAnalyzer.analyzeNight(
            forecasts: forecasts,
            sunEventsToday: sunEventsToday,
            sunEventsTomorrow: sunEventsTomorrow,
            moonInfo: moonInfo,
            latitude: location.latitude,
            longitude: location.longitude,
            for: today
        )

        let cachedLocation = CachedLocation(
            name: location.name,
            latitude: location.latitude,
            longitude: location.longitude
        )
        let conditions = ViewingConditions(
            fetchedAt: Date(),
            location: cachedLocation,
            hourlyForecasts: forecasts,
            dailySunEvents: [sunEventsToday, sunEventsTomorrow],
            dailyMoonInfo: [moonInfo],
            issPasses: [],
            fogScore: FogCalculator.calculateCurrent(from: forecasts)
        )
        WidgetCacheStore.save(conditions)

        return NightConditionsEntry(date: Date(), assessment: assessment)
    }
}

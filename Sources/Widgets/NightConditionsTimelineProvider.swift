import SharedCode
import WidgetKit
import SwiftUI
import os.log

private let widgetLogger = Logger(subsystem: "com.astroviewing.conditions.widget", category: "Widget")

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
        guard let location = SharedStorage.loadWidgetLocation() else {
            widgetLogger.error("No location configured for widget")
            return nil
        }

        let weatherService = WeatherService()
        let astronomyService = AstronomyService()

        let forecasts: [HourlyForecast]
        do {
            forecasts = try await weatherService.fetchForecast(
                latitude: location.latitude,
                longitude: location.longitude,
                days: 3
            )
            widgetLogger.info("Fetched \(forecasts.count) hourly forecasts from API")
        } catch {
            widgetLogger.error("Failed to fetch weather forecast: \(error.localizedDescription)")
            if let cached = SharedStorage.loadWidgetConditions() {
                widgetLogger.info("Falling back to cached weather data")
                forecasts = cached.hourlyForecasts
            } else {
                widgetLogger.error("No cached weather data available as fallback")
                return nil
            }
        }

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
        SharedStorage.saveWidgetConditions(conditions)

        return NightConditionsEntry(date: Date(), assessment: assessment)
    }
}

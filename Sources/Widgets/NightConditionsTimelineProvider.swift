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
            let nextHour = Date().addingTimeInterval(3600)
            completion(Timeline(entries: [entry], policy: .after(nextHour)))
        }
    }

    private func buildEntry() async -> NightConditionsEntry? {
        guard let location = AppGroupStorage.loadSelectedLocationForWidget() else {
            widgetLogger.error("No location configured for widget")
            return nil
        }

        let weatherService = WeatherService()
        let astronomyService = AstronomyService()

        let forecasts: [HourlyForecast]
        let fetchedAt: Date
        do {
            forecasts = try await weatherService.fetchForecast(
                latitude: location.latitude,
                longitude: location.longitude,
                days: 2
            )
            fetchedAt = Date()
            widgetLogger.info("Fetched \(forecasts.count) hourly forecasts from API")
        } catch {
            widgetLogger.error("Failed to fetch weather forecast: \(error.localizedDescription)")
            if let cached = await AppGroupStorage.loadWidgetConditionsAsync(),
               cached.isFreshForWidget,
               cached.location.matches(latitude: location.latitude, longitude: location.longitude) {
                widgetLogger.info("Falling back to cached weather data")
                forecasts = cached.hourlyForecasts
                fetchedAt = cached.fetchedAt
            } else {
                widgetLogger.error("No cached weather data available as fallback")
                return nil
            }
        }

        let tz = await LocationTimeZoneResolver.resolve(latitude: location.latitude, longitude: location.longitude)
        let calendar = LocationTimeZoneResolver.calendar(for: tz)
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
        let moonInfoTomorrow = await astronomyService.calculateMoonInfo(
            latitude: location.latitude,
            longitude: location.longitude,
            on: tomorrow
        )

        let assessment = NightQualityAnalyzer.analyzeNight(
            forecasts: forecasts,
            sunEventsToday: sunEventsToday,
            sunEventsTomorrow: sunEventsTomorrow,
            moonInfo: moonInfo,
            latitude: location.latitude,
            longitude: location.longitude,
            for: today,
            calendar: calendar
        )

        let cachedLocation = CachedLocation(
            name: location.name,
            latitude: location.latitude,
            longitude: location.longitude
        )
        let conditions = ViewingConditions(
            fetchedAt: fetchedAt,
            location: cachedLocation,
            hourlyForecasts: forecasts,
            dailySunEvents: [sunEventsToday, sunEventsTomorrow],
            dailyMoonInfo: [moonInfo, moonInfoTomorrow],
            issPasses: [],
            fogScore: FogCalculator.calculateCurrent(from: forecasts),
            timeZoneIdentifier: tz.identifier
        )
        await AppGroupStorage.saveWidgetConditionsAsync(conditions)

        return NightConditionsEntry(date: Date(), assessment: assessment, timeZone: tz)
    }
}

private extension ViewingConditions {
    var isFreshForWidget: Bool {
        Date().timeIntervalSince(fetchedAt) <= 3600
    }
}

private extension CachedLocation {
    func matches(latitude: Double, longitude: Double) -> Bool {
        abs(self.latitude - latitude) <= 0.01 &&
            abs(self.longitude - longitude) <= 0.01
    }
}

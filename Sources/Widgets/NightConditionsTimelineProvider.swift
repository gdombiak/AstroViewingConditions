import SharedCode
import WidgetKit
import SwiftUI
import os.log

private let widgetLogger = Logger(subsystem: "com.astroviewing.conditions.widget", category: "Widget")
private let widgetCacheMaxAge: TimeInterval = 3600

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

        if let cached = await AppGroupStorage.loadWidgetConditionsAsync(),
           cached.isFreshForLocalDay(within: widgetCacheMaxAge),
           cached.locationMatches(latitude: location.latitude, longitude: location.longitude) {
            widgetLogger.info("Using fresh cached weather data")
            return await buildEntry(from: cached, location: location)
        }

        let cachedLocation = CachedLocation(
            name: location.name,
            latitude: location.latitude,
            longitude: location.longitude
        )
        let conditions: ViewingConditions
        do {
            conditions = try await ConditionsProvider().fetchConditions(
                for: cachedLocation,
                days: 2
            )
            widgetLogger.info("Fetched \(conditions.hourlyForecasts.count) hourly forecasts from API")
        } catch {
            widgetLogger.error("Failed to fetch widget conditions: \(error.localizedDescription)")
            if let cached = await AppGroupStorage.loadWidgetConditionsAsync(),
               cached.isFreshForWidget,
               cached.location.matches(latitude: location.latitude, longitude: location.longitude) {
                widgetLogger.info("Falling back to cached weather data")
                return await buildEntry(from: cached, location: location)
            } else {
                widgetLogger.error("No cached weather data available as fallback")
                return nil
            }
        }

        await AppGroupStorage.saveWidgetConditionsAsync(conditions)

        return await buildEntry(from: conditions, location: location)
    }

    private func buildEntry(
        from conditions: ViewingConditions,
        location: (latitude: Double, longitude: Double, name: String)
    ) async -> NightConditionsEntry? {
        guard let sunEventsToday = conditions.dailySunEvents.first,
              let sunEventsTomorrow = conditions.dailySunEvents.dropFirst().first,
              let moonInfo = conditions.dailyMoonInfo.first else {
            widgetLogger.error("Cached widget conditions are missing astronomy data")
            return nil
        }

        let tz: TimeZone
        if let cachedTimeZone = conditions.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) {
            tz = cachedTimeZone
        } else {
            tz = await LocationTimeZoneResolver.resolve(latitude: location.latitude, longitude: location.longitude)
        }
        let calendar = LocationTimeZoneResolver.calendar(for: tz)
        let assessment = NightQualityAnalyzer.analyzeNight(
            forecasts: conditions.hourlyForecasts,
            sunEventsToday: sunEventsToday,
            sunEventsTomorrow: sunEventsTomorrow,
            moonInfo: moonInfo,
            latitude: location.latitude,
            longitude: location.longitude,
            for: calendar.startOfDay(for: Date()),
            calendar: calendar
        )

        return NightConditionsEntry(date: Date(), assessment: assessment, timeZone: tz)
    }
}

private extension ViewingConditions {
    var isFreshForWidget: Bool {
        isFreshForLocalDay(within: widgetCacheMaxAge)
    }
}

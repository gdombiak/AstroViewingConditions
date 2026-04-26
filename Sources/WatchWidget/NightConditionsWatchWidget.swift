import WidgetKit
import SwiftUI
import SharedCode
import os.log

private let widgetLogger = Logger(subsystem: "com.astroviewing.conditions.watchwidget", category: "WatchWidget")

struct NightConditionsEntry: TimelineEntry, Sendable {
    let date: Date
    let assessment: NightQualityAssessment

    static var placeholder: NightConditionsEntry {
        NightConditionsEntry(
            date: Date(),
            assessment: NightQualityAssessment(
                rating: .good,
                summary: "Good conditions for stargazing tonight.",
                details: NightQualityAssessment.Details(
                    cloudCoverScore: 25,
                    fogScoreAvg: 15,
                    moonIlluminationAvg: 12,
                    windSpeedAvg: 2.5
                ),
                bestWindow: nil,
                hourlyRatings: [],
                nightStart: Date(),
                nightEnd: Date().addingTimeInterval(8 * 3600),
                trend: .stable,
                firstHalfScore: nil,
                secondHalfScore: nil
            )
        )
    }
}

struct WatchProvider: TimelineProvider {
    func placeholder(in context: Context) -> NightConditionsEntry {
        return .placeholder
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
            let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }

    private func buildEntry() async -> NightConditionsEntry? {
        let location: (latitude: Double, longitude: Double, name: String)
        
        if let saved = AppGroupStorage.loadSelectedLocationForWidget() {
            location = saved
        } else {
            widgetLogger.info("No saved location, requesting current GPS location")
            let locManager = LocationManager()
            locManager.requestAuthorization()
            
            do {
                let coord = try await locManager.getCurrentLocation()
                location = (coord.latitude, coord.longitude, "Current Location")

                LocationStorageService.shared.saveSelectedLocation(SelectedLocation(
                    source: .currentGPS,
                    name: location.name,
                    latitude: location.latitude,
                    longitude: location.longitude
                ))
            } catch {
                widgetLogger.error("Failed to get current GPS location: \(error.localizedDescription)")
                return nil
            }
        }

        let cachedLocation = CachedLocation(name: location.name, latitude: location.latitude, longitude: location.longitude)

        let weatherService = WeatherService()
        let astronomyService = AstronomyService()

        let forecasts: [HourlyForecast]
        do {
            forecasts = try await weatherService.fetchForecast(latitude: location.latitude, longitude: location.longitude, days: 3)
            widgetLogger.info("Fetched \(forecasts.count) hourly forecasts from API")
        } catch {
            widgetLogger.error("Failed to fetch weather forecast: \(error.localizedDescription)")
            if let cached = AppGroupStorage.loadWidgetConditions() {
                widgetLogger.info("Falling back to cached weather data")
                forecasts = cached.hourlyForecasts
            } else {
                widgetLogger.error("No cached weather data available as fallback")
                return nil
            }
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        let sunEventsToday = await astronomyService.calculateSunEvents(latitude: location.latitude, longitude: location.longitude, on: today)
        let sunEventsTomorrow = await astronomyService.calculateSunEvents(latitude: location.latitude, longitude: location.longitude, on: tomorrow)
        let moonInfo = await astronomyService.calculateMoonInfo(latitude: location.latitude, longitude: location.longitude, on: today)

        let assessment = NightQualityAnalyzer.analyzeNight(
            forecasts: forecasts,
            sunEventsToday: sunEventsToday,
            sunEventsTomorrow: sunEventsTomorrow,
            moonInfo: moonInfo,
            latitude: location.latitude,
            longitude: location.longitude,
            for: today
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
        AppGroupStorage.saveWidgetConditions(conditions)

        return NightConditionsEntry(date: Date(), assessment: assessment)
    }
}

struct WatchWidgetEntryView: View {
    var entry: NightConditionsEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularComplicationView(assessment: entry.assessment)
                .containerBackground(.clear, for: .widget)
        case .accessoryRectangular:
            RectangularComplicationView(assessment: entry.assessment)
                .containerBackground(.clear, for: .widget)
        case .accessoryInline:
            InlineComplicationView(assessment: entry.assessment)
                .containerBackground(.clear, for: .widget)
         case .accessoryCorner:
             CornerComplicationView(assessment: entry.assessment)
        default:
            CircularComplicationView(assessment: entry.assessment)
                .containerBackground(.clear, for: .widget)
        }
    }
}

struct NightConditionsWatchWidget: Widget {
    let kind: String = "NightConditionsWatchWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchProvider()) { entry in
            WatchWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Night Conditions")
        .description("Tonight's stargazing conditions")
        .supportedFamilies([
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryCorner,
        ])
    }
}

@main
struct WatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        NightConditionsWatchWidget()
    }
}

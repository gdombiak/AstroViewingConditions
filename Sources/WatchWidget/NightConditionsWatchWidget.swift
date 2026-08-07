import WidgetKit
import SwiftUI
import SharedCode
import os.log

private let widgetLogger = Logger(subsystem: "com.astroviewing.conditions.watchwidget", category: "WatchWidget")
private let watchWidgetCacheMaxAge: TimeInterval = 3600

struct NightConditionsEntry: TimelineEntry, Sendable {
    let date: Date
    let assessment: NightQualityAssessment
    /// Overall headline (OQ when Phase 4B saved-location enhancement is associated).
    let headlineScore: Int
    /// Whether the headline is LP-backed OQ or night-only fallback (for accessibility).
    let scorePresentationMode: WatchHeadlineScorePresentationMode

    init(
        date: Date,
        assessment: NightQualityAssessment,
        headlineScore: Int? = nil,
        scorePresentationMode: WatchHeadlineScorePresentationMode = .nightConditionsFallback
    ) {
        self.date = date
        self.assessment = assessment
        self.headlineScore = headlineScore ?? assessment.calculatedScore
        self.scorePresentationMode = scorePresentationMode
    }

    static var placeholder: NightConditionsEntry {
        let assessment = NightQualityAssessment(
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
        return NightConditionsEntry(
            date: Date(),
            assessment: assessment,
            headlineScore: assessment.calculatedScore,
            scorePresentationMode: .nightConditionsFallback
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
            let nextUpdate = Date().addingTimeInterval(3600)
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }

    private func buildEntry() async -> NightConditionsEntry? {
        let location: (latitude: Double, longitude: Double, name: String)
        
        if let saved = AppGroupStorage.loadSelectedLocationForWidget() {
            location = (saved.latitude, saved.longitude, saved.name)
        } else {
            widgetLogger.info("No saved location, requesting current GPS location")
            let locManager = await MainActor.run { LocationManager() }
            await locManager.requestAuthorization()
            
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

        if let cached = await AppGroupStorage.loadWatchNightConditionsAsync(),
           cached.isFreshForLocalDay(within: watchWidgetCacheMaxAge),
           cached.locationMatches(latitude: location.latitude, longitude: location.longitude) {
            widgetLogger.info("Using fresh cached weather data")
            return await buildEntry(from: cached, location: location)
        }

        let conditions: ViewingConditions
        do {
            conditions = try await ConditionsProvider().fetchConditions(
                for: cachedLocation,
                days: 2
            )
            widgetLogger.info("Fetched \(conditions.hourlyForecasts.count) hourly forecasts from API")
        } catch {
            widgetLogger.error("Failed to fetch watch widget conditions: \(error.localizedDescription)")
            if let cached = await AppGroupStorage.loadWatchNightConditionsAsync(),
               cached.isFreshForWatchNight,
               cached.location.matches(latitude: location.latitude, longitude: location.longitude) {
                widgetLogger.info("Falling back to cached weather data")
                return await buildEntry(from: cached, location: location)
            } else {
                widgetLogger.error("No cached weather data available as fallback")
                return nil
            }
        }

        await AppGroupStorage.saveWatchNightConditionsAsync(conditions)

        return await buildEntry(from: conditions, location: location)
    }

    private func buildEntry(
        from conditions: ViewingConditions,
        location: (latitude: Double, longitude: Double, name: String)
    ) async -> NightConditionsEntry? {
        guard let sunEventsToday = conditions.dailySunEvents.first,
              let sunEventsTomorrow = conditions.dailySunEvents.dropFirst().first,
              let moonInfo = conditions.dailyMoonInfo.first else {
            widgetLogger.error("Cached watch widget conditions are missing astronomy data")
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

        let resolved = await Self.resolveHeadline(
            conditions: conditions,
            nightScore: assessment.calculatedScore
        )
        return NightConditionsEntry(
            date: Date(),
            assessment: assessment,
            headlineScore: resolved.score,
            scorePresentationMode: resolved.presentationMode
        )
    }

    /// Loads recomputed watch OQ when associated with these conditions (saved location only).
    private static func resolveHeadline(
        conditions: ViewingConditions,
        nightScore: Int
    ) async -> (score: Int, presentationMode: WatchHeadlineScorePresentationMode) {
        guard let document = await AppGroupStorage.loadWatchObservingQualityAsync() else {
            return (nightScore, .nightConditionsFallback)
        }
        let selected = AppGroupStorage.loadSelectedLocationForWidget()
        guard WatchObservingQualityCanonicalizer.isAssociated(
            document: document,
            conditions: conditions,
            selectedLocation: selected
        ) else {
            return (nightScore, .nightConditionsFallback)
        }
        // Canonical brightness availability — not score equality.
        let mode = WatchHeadlineScorePresentationMode.from(
            brightnessAvailability: document.snapshot.brightnessAvailability
        )
        switch mode {
        case .observingQuality:
            return (document.snapshot.observingQualityScore, .observingQuality)
        case .nightConditionsFallback:
            return (nightScore, .nightConditionsFallback)
        }
    }
}

private extension ViewingConditions {
    var isFreshForWatchNight: Bool {
        isFreshForLocalDay(within: watchWidgetCacheMaxAge)
    }
}

struct WatchWidgetEntryView: View {
    var entry: NightConditionsEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularComplicationView(
                assessment: entry.assessment,
                headlineScore: entry.headlineScore,
                scorePresentationMode: entry.scorePresentationMode
            )
            .containerBackground(.clear, for: .widget)
        case .accessoryRectangular:
            RectangularComplicationView(
                assessment: entry.assessment,
                headlineScore: entry.headlineScore,
                scorePresentationMode: entry.scorePresentationMode
            )
            .containerBackground(.clear, for: .widget)
        case .accessoryInline:
            InlineComplicationView(
                assessment: entry.assessment,
                headlineScore: entry.headlineScore,
                scorePresentationMode: entry.scorePresentationMode
            )
            .containerBackground(.clear, for: .widget)
         case .accessoryCorner:
             CornerComplicationView(
                assessment: entry.assessment,
                headlineScore: entry.headlineScore,
                scorePresentationMode: entry.scorePresentationMode
             )
        default:
            CircularComplicationView(
                assessment: entry.assessment,
                headlineScore: entry.headlineScore,
                scorePresentationMode: entry.scorePresentationMode
            )
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

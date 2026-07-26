import SharedCode
import WidgetKit
import os.log

private let widgetLogger = Logger(
    subsystem: "com.astroviewing.conditions.widget",
    category: "NightConditions"
)

struct Provider: TimelineProvider {
    private static let timelineReevaluationInterval: TimeInterval = 3600
    private static let fallbackMaximumAge: TimeInterval = 24 * 3600

    func placeholder(in context: Context) -> NightConditionsEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @Sendable @escaping (NightConditionsEntry) -> Void) {
        guard !context.isPreview else {
            completion(.placeholder)
            return
        }
        Task { @Sendable in
            completion(await buildEntry())
        }
    }

    func getTimeline(in context: Context, completion: @Sendable @escaping (Timeline<NightConditionsEntry>) -> Void) {
        Task { @Sendable in
            let referenceDate = Date()
            widgetLogger.info("Timeline invocation")
            let entry = await buildEntry(referenceDate: referenceDate)
            let nextRequestDate = referenceDate.addingTimeInterval(
                Self.timelineReevaluationInterval
            )
            widgetLogger.info(
                "Next timeline request: \(nextRequestDate.description, privacy: .public)"
            )
            completion(Timeline(entries: [entry], policy: .after(nextRequestDate)))
        }
    }

    private func buildEntry(referenceDate: Date = Date()) async -> NightConditionsEntry {
        guard let location = AppGroupStorage.loadSelectedLocationForWidget() else {
            widgetLogger.error("No location configured for widget")
            return NightConditionsEntry(date: referenceDate, state: .unavailable(.noLocation))
        }
        widgetLogger.info("Selected location: \(location.name, privacy: .public)")
        let cachedSummary = await AppGroupStorage.loadWidgetNightSummaryAsync()
        let cachedLocation = CachedLocation(
            id: location.source == .saved ? location.id : nil,
            name: location.name, latitude: location.latitude, longitude: location.longitude
        )
        let refreshService = WidgetConditionsRefreshService()
        do {
            let conditions = try await refreshService.conditions(
                for: cachedLocation, referenceDate: referenceDate
            )
            widgetLogger.info(
                "Conditions returned; fetchedAt: \(conditions.fetchedAt.description, privacy: .public)"
            )
            guard let summary = WidgetNightSummary.make(from: conditions) else {
                widgetLogger.warning("Returned conditions could not build a Night Conditions summary")
                return await fallbackEntry(
                    cachedSummary: cachedSummary,
                    location: location,
                    cachedLocation: cachedLocation,
                    refreshService: refreshService,
                    referenceDate: referenceDate
                )
            }
            await AppGroupStorage.saveWidgetNightSummaryAsync(summary)
            widgetLogger.info("Rebuilt and saved Night Conditions summary")
            return NightConditionsEntry(date: referenceDate, state: .available(summary))
        } catch {
            widgetLogger.warning(
                "Conditions service failed: \(error.localizedDescription, privacy: .public)"
            )
            return await fallbackEntry(
                cachedSummary: cachedSummary,
                location: location,
                cachedLocation: cachedLocation,
                refreshService: refreshService,
                referenceDate: referenceDate
            )
        }
    }

    private func fallbackEntry(
        cachedSummary: WidgetNightSummary?,
        location: SelectedLocation,
        cachedLocation: CachedLocation,
        refreshService: WidgetConditionsRefreshService,
        referenceDate: Date
    ) async -> NightConditionsEntry {
        if let cachedSummary,
           cachedSummary.locationMatches(location),
           cachedSummary.isFreshForLocalDay(
               within: Self.fallbackMaximumAge,
               relativeTo: referenceDate
           ) {
            widgetLogger.info("Using matching last-known-good Night Conditions summary")
            return NightConditionsEntry(date: referenceDate, state: .available(cachedSummary))
        }
        if let staleConditions = await refreshService.matchingCachedConditions(for: cachedLocation),
           staleConditions.isFreshForLocalDay(
               within: Self.fallbackMaximumAge,
               relativeTo: referenceDate
           ),
           let summary = WidgetNightSummary.make(from: staleConditions) {
            widgetLogger.info("Using matching stale shared conditions fallback")
            return NightConditionsEntry(date: referenceDate, state: .available(summary))
        }
        widgetLogger.warning("No usable Night Conditions fallback")
        return unavailableEntry(from: cachedSummary, location: location, date: referenceDate)
    }

    private func unavailableEntry(
        from summary: WidgetNightSummary?, location: SelectedLocation, date: Date
    ) -> NightConditionsEntry {
        guard let summary else { return .init(date: date, state: .unavailable(.noForecast)) }
        return .init(
            date: date,
            state: .unavailable(summary.locationMatches(location) ? .staleForecast : .locationUnavailable)
        )
    }
}

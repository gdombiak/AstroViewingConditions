import SharedCode
import WidgetKit
import os.log

private let widgetLogger = Logger(subsystem: "com.astroviewing.conditions.widget", category: "Widget")
private let widgetCacheMaxAge: TimeInterval = 3600

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> NightConditionsEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @Sendable @escaping (NightConditionsEntry) -> Void) {
        Task { @Sendable in
            completion(await buildEntry())
        }
    }

    func getTimeline(in context: Context, completion: @Sendable @escaping (Timeline<NightConditionsEntry>) -> Void) {
        Task { @Sendable in
            let entry = await buildEntry()
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600))))
        }
    }

    private func buildEntry() async -> NightConditionsEntry {
        guard let location = AppGroupStorage.loadSelectedLocationForWidget() else {
            widgetLogger.error("No location configured for widget")
            return NightConditionsEntry(date: Date(), state: .unavailable(.noLocation))
        }
        let referenceDate = Date()
        let cachedSummary = await AppGroupStorage.loadWidgetNightSummaryAsync()
        if let cachedSummary,
           cachedSummary.locationMatches(location),
           cachedSummary.isFreshForLocalDay(within: widgetCacheMaxAge, relativeTo: referenceDate) {
            return NightConditionsEntry(date: referenceDate, state: .available(cachedSummary))
        }

        let cachedLocation = CachedLocation(
            id: location.source == .saved ? location.id : nil,
            name: location.name, latitude: location.latitude, longitude: location.longitude
        )
        let refreshService = WidgetConditionsRefreshService()
        do {
            let conditions = try await refreshService.conditions(
                for: cachedLocation, referenceDate: referenceDate
            )
            guard let summary = WidgetNightSummary.make(from: conditions) else {
                widgetLogger.warning("Fresh widget conditions could not be analyzed")
                return unavailableEntry(from: cachedSummary, location: location, date: referenceDate)
            }
            await AppGroupStorage.saveWidgetNightSummaryAsync(summary)
            return NightConditionsEntry(date: referenceDate, state: .available(summary))
        } catch {
            widgetLogger.warning("Widget conditions refresh failed: \(error.localizedDescription)")
            if let cachedSummary,
               cachedSummary.locationMatches(location),
               cachedSummary.isFreshForLocalDay(within: 24 * 3600, relativeTo: referenceDate) {
                return NightConditionsEntry(date: referenceDate, state: .available(cachedSummary))
            }
            if let staleConditions = await refreshService.matchingCachedConditions(for: cachedLocation),
               staleConditions.isFreshForLocalDay(within: 24 * 3600, relativeTo: referenceDate),
               let summary = WidgetNightSummary.make(from: staleConditions) {
                return NightConditionsEntry(date: referenceDate, state: .available(summary))
            }
            return unavailableEntry(from: cachedSummary, location: location, date: referenceDate)
        }
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

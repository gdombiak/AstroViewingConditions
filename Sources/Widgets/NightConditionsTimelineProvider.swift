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

        guard let summary = await AppGroupStorage.loadWidgetNightSummaryAsync() else {
            widgetLogger.error("No cached widget summary available")
            return NightConditionsEntry(date: Date(), state: .unavailable(.noForecast))
        }

        guard summary.locationMatches(latitude: location.latitude, longitude: location.longitude) else {
            widgetLogger.warning("Cached widget summary is for a different location")
            return NightConditionsEntry(date: Date(), state: .unavailable(.locationUnavailable))
        }

        guard summary.isFreshForLocalDay(within: widgetCacheMaxAge) else {
            widgetLogger.info("Cached widget summary is stale")
            return NightConditionsEntry(date: Date(), state: .unavailable(.staleForecast))
        }

        return NightConditionsEntry(date: Date(), state: .available(summary))
    }
}

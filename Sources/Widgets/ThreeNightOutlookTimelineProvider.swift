import SharedCode
import WidgetKit
import os

private let outlookWidgetLogger = Logger(subsystem: "com.astroviewing.conditions.widget", category: "ThreeNightOutlook")

struct ThreeNightOutlookTimelineProvider: TimelineProvider {
    static let timelineReevaluationInterval: TimeInterval = 3600
    static let payloadMaximumAge = WidgetThreeNightOutlookSummary.maximumAge

    func placeholder(in context: Context) -> ThreeNightOutlookEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @Sendable @escaping (ThreeNightOutlookEntry) -> Void) {
        Task { @Sendable in completion(await buildEntry()) }
    }

    func getTimeline(
        in context: Context,
        completion: @Sendable @escaping (Timeline<ThreeNightOutlookEntry>) -> Void
    ) {
        Task { @Sendable in
            let entry = await buildEntry()
            completion(Timeline(
                entries: [entry],
                policy: .after(Date().addingTimeInterval(Self.timelineReevaluationInterval))
            ))
        }
    }

    func buildEntry(referenceDate: Date = Date()) async -> ThreeNightOutlookEntry {
        guard let location = AppGroupStorage.loadSelectedLocationForWidget() else {
            return .init(date: referenceDate, state: .unavailable(.noLocation))
        }
        let cachedSummary = await AppGroupStorage.loadWidgetThreeNightOutlookSummaryAsync()
        if let cachedSummary,
           ThreeNightOutlookEntryResolver.resolve(
            summary: cachedSummary, selectedLocation: location, referenceDate: referenceDate,
            maximumAge: Self.payloadMaximumAge
           ) == .available {
            return .init(date: referenceDate, state: .available(cachedSummary))
        }

        let cachedLocation = CachedLocation(
            id: location.source == .saved ? location.id : nil,
            name: location.name, latitude: location.latitude, longitude: location.longitude
        )
        do {
            let conditions = try await WidgetConditionsRefreshService().conditions(
                for: cachedLocation, referenceDate: referenceDate
            )
            let decision = ThreeNightOutlookWidgetPayloadBuilder.publicationDecision(
                conditions: conditions, existingSummary: cachedSummary, referenceDate: referenceDate,
                timeZone: conditions.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            )
            switch decision {
            case let .publish(summary), let .unavailable(summary):
                await AppGroupStorage.saveWidgetThreeNightOutlookSummaryAsync(summary)
                return entry(for: summary, location: location, date: referenceDate)
            case .preserveExisting:
                if let cachedSummary { return entry(for: cachedSummary, location: location, date: referenceDate) }
            }
        } catch {
            outlookWidgetLogger.warning("Three-night outlook refresh failed: \(error.localizedDescription)")
        }

        // A valid active-night payload remains more useful than an unavailable
        // state if a transient refresh fails, even when it just exceeded age.
        if let cachedSummary,
           cachedSummary.locationMatches(location),
           cachedSummary.matchesCurrentObservingNight(relativeTo: referenceDate) {
            return .init(date: referenceDate, state: .available(cachedSummary))
        }
        return .init(date: referenceDate, state: .unavailable(cachedSummary == nil ? .noCache : .stale))
    }

    private func entry(
        for summary: WidgetThreeNightOutlookSummary,
        location: SelectedLocation,
        date: Date
    ) -> ThreeNightOutlookEntry {
        switch ThreeNightOutlookEntryResolver.resolve(
            summary: summary, selectedLocation: location, referenceDate: date,
            maximumAge: Self.payloadMaximumAge
        ) {
        case .available: return .init(date: date, state: .available(summary))
        case .noLocation: return .init(date: date, state: .unavailable(.noLocation))
        case .noCache: return .init(date: date, state: .unavailable(.noCache))
        case .stale: return .init(date: date, state: .unavailable(.stale))
        case .locationMismatch: return .init(date: date, state: .unavailable(.locationMismatch))
        case .observingNightMismatch: return .init(date: date, state: .unavailable(.observingNightMismatch))
        case .unavailable: return .init(date: date, state: .unavailable(.unavailable))
        }
    }
}

import SharedCode
import WidgetKit
import os

private let outlookWidgetLogger = Logger(subsystem: "com.astroviewing.conditions.widget", category: "ThreeNightOutlook")

struct ThreeNightOutlookTimelineProvider: TimelineProvider {
    static let timelineReevaluationInterval: TimeInterval = 3600

    func placeholder(in context: Context) -> ThreeNightOutlookEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @Sendable @escaping (ThreeNightOutlookEntry) -> Void) {
        guard !context.isPreview else {
            completion(.placeholder)
            return
        }
        Task { @Sendable in completion(await buildEntry()) }
    }

    func getTimeline(
        in context: Context,
        completion: @Sendable @escaping (Timeline<ThreeNightOutlookEntry>) -> Void
    ) {
        Task { @Sendable in
            let referenceDate = Date()
            outlookWidgetLogger.info("Timeline invocation")
            let entry = await buildEntry(referenceDate: referenceDate)
            let nextRequestDate = referenceDate.addingTimeInterval(
                Self.timelineReevaluationInterval
            )
            outlookWidgetLogger.info(
                "Next timeline request: \(nextRequestDate.description, privacy: .public)"
            )
            completion(Timeline(
                entries: [entry],
                policy: .after(nextRequestDate)
            ))
        }
    }

    func buildEntry(referenceDate: Date = Date()) async -> ThreeNightOutlookEntry {
        guard let location = AppGroupStorage.loadSelectedLocationForWidget() else {
            return .init(date: referenceDate, state: .unavailable(.noLocation))
        }
        outlookWidgetLogger.info("Selected location: \(location.name, privacy: .public)")
        let cachedSummary = await AppGroupStorage.loadWidgetThreeNightOutlookSummaryAsync()
        let cachedLocation = CachedLocation(
            id: location.source == .saved ? location.id : nil,
            name: location.name, latitude: location.latitude, longitude: location.longitude
        )
        do {
            let result = try await SharedConditionsRepository().conditions(
                for: cachedLocation, referenceDate: referenceDate
            )
            let conditions = result.conditions
            outlookWidgetLogger.info(
                "Conditions returned; fetchedAt: \(conditions.fetchedAt.description, privacy: .public)"
            )
            let decision = ThreeNightOutlookWidgetPayloadBuilder.publicationDecision(
                conditions: conditions, existingSummary: cachedSummary, referenceDate: referenceDate,
                timeZone: conditions.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            )
            switch decision {
            case let .publish(summary), let .unavailable(summary):
                await AppGroupStorage.saveWidgetThreeNightOutlookSummaryAsync(summary)
                outlookWidgetLogger.info("Rebuilt and saved Three-Night Outlook summary")
                return entry(
                    for: summary,
                    location: location,
                    date: referenceDate,
                    dataStatus: .normal(conditions: conditions)
                )
            case .preserveExisting:
                if let cachedSummary {
                    outlookWidgetLogger.info("Preserving active previous-night Outlook summary")
                    return entry(
                        for: cachedSummary,
                        location: location,
                        date: referenceDate,
                        dataStatus: .normal(summary: cachedSummary)
                    )
                }
            }
        } catch {
            outlookWidgetLogger.warning(
                "Conditions service failed: \(error.localizedDescription, privacy: .public)"
            )
        }

        // A valid active-night payload remains more useful than an unavailable
        // state if a transient refresh fails, even when it just exceeded age.
        if let cachedSummary,
           cachedSummary.locationMatches(location),
           cachedSummary.matchesCurrentObservingNight(relativeTo: referenceDate) {
            outlookWidgetLogger.info("Using matching last-known-good Outlook summary")
            return .init(
                date: referenceDate,
                state: .available(cachedSummary),
                dataStatus: .fallback(summary: cachedSummary)
            )
        }
        outlookWidgetLogger.warning("No usable Outlook summary fallback")
        return .init(date: referenceDate, state: .unavailable(cachedSummary == nil ? .noCache : .stale))
    }

    private func entry(
        for summary: WidgetThreeNightOutlookSummary,
        location: SelectedLocation,
        date: Date,
        dataStatus: WidgetDataStatus
    ) -> ThreeNightOutlookEntry {
        switch ThreeNightOutlookEntryResolver.resolve(
            summary: summary, selectedLocation: location, referenceDate: date
        ) {
        case .available: return .init(date: date, state: .available(summary), dataStatus: dataStatus)
        case .noLocation: return .init(date: date, state: .unavailable(.noLocation))
        case .noCache: return .init(date: date, state: .unavailable(.noCache))
        case .stale: return .init(date: date, state: .unavailable(.stale))
        case .locationMismatch: return .init(date: date, state: .unavailable(.locationMismatch))
        case .observingNightMismatch: return .init(date: date, state: .unavailable(.observingNightMismatch))
        case .unavailable: return .init(date: date, state: .unavailable(.unavailable))
        }
    }

}

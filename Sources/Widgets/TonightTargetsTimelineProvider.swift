import SharedCode
import WidgetKit
import os

private let targetsWidgetLogger = Logger(subsystem: "com.astroviewing.conditions.widget", category: "TonightTargets")

struct TonightTargetsTimelineProvider: TimelineProvider {
    static let timelineReevaluationInterval: TimeInterval = 3600
    static let payloadMaximumAge = WidgetTonightTargetsSummary.maximumAge

    func placeholder(in context: Context) -> TonightTargetsEntry {
        .placeholder
    }

    func getSnapshot(
        in context: Context,
        completion: @Sendable @escaping (TonightTargetsEntry) -> Void
    ) {
        Task { @Sendable in
            completion(await buildEntry())
        }
    }

    func getTimeline(
        in context: Context,
        completion: @Sendable @escaping (Timeline<TonightTargetsEntry>) -> Void
    ) {
        Task { @Sendable in
            let entry = await buildEntry()
            completion(Timeline(
                entries: [entry],
                policy: .after(
                    Date().addingTimeInterval(Self.timelineReevaluationInterval)
                )
            ))
        }
    }

    private func buildEntry(referenceDate: Date = Date()) async -> TonightTargetsEntry {
        guard let location = AppGroupStorage.loadSelectedLocationForWidget() else {
            return TonightTargetsEntry(
                date: referenceDate,
                state: .unavailable(.noLocation)
            )
        }

        let cachedSummary = await AppGroupStorage.loadWidgetTonightTargetsSummaryAsync()
        if let cachedSummary, isCurrent(cachedSummary, location: location, referenceDate: referenceDate) {
            return entry(for: cachedSummary, date: referenceDate)
        }

        let cachedLocation = CachedLocation(
            id: location.source == .saved ? location.id : nil,
            name: location.name, latitude: location.latitude, longitude: location.longitude
        )
        do {
            let conditions = try await WidgetConditionsRefreshService().conditions(
                for: cachedLocation, referenceDate: referenceDate
            )
            let decision = TonightTargetsWidgetContextResolver.publicationDecision(
                conditions: conditions, existingSummary: cachedSummary,
                referenceDate: referenceDate,
                timeZone: conditions.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            )
            switch decision {
            case let .publish(resolution):
                let summary = TonightTargetsWidgetRefreshPipeline.makeSummary(
                    conditions: conditions,
                    resolution: resolution
                )
                await AppGroupStorage.saveWidgetTonightTargetsSummaryAsync(summary)
                return entry(for: summary, date: referenceDate)
            case .preserveExisting:
                if let cachedSummary { return entry(for: cachedSummary, date: referenceDate) }
            case .unavailable:
                let summary = TonightTargetsWidgetPayloadBuilder.makeUnavailableSummary(
                    generatedAt: conditions.fetchedAt, location: conditions.location,
                    timeZone: conditions.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
                        ?? LocationTimeZoneResolver.approximate(longitude: conditions.location.longitude),
                    referenceDate: referenceDate
                )
                await AppGroupStorage.saveWidgetTonightTargetsSummaryAsync(summary)
                return entry(for: summary, date: referenceDate)
            }
        } catch {
            targetsWidgetLogger.warning("Widget targets refresh failed: \(error.localizedDescription)")
        }

        if let cachedSummary,
           cachedSummary.locationMatches(location),
           cachedSummary.matchesCurrentObservingNight(relativeTo: referenceDate) {
            return entry(for: cachedSummary, date: referenceDate)
        }
        return .init(date: referenceDate, state: .unavailable(cachedSummary == nil ? .noCache : .stale))
    }

    private func isCurrent(
        _ summary: WidgetTonightTargetsSummary, location: SelectedLocation, referenceDate: Date
    ) -> Bool {
        summary.locationMatches(location)
            && summary.matchesCurrentObservingNight(relativeTo: referenceDate)
            && summary.isWithinMaximumAge(Self.payloadMaximumAge, relativeTo: referenceDate)
    }

    private func entry(for summary: WidgetTonightTargetsSummary, date: Date) -> TonightTargetsEntry {
        switch summary.status {
        case .available where !summary.targets.isEmpty:
            return TonightTargetsEntry(date: date, state: .available(summary))
        case .noTargets:
            return TonightTargetsEntry(date: date, state: .noTargets)
        case .unavailable, .available:
            return TonightTargetsEntry(
                date: date,
                state: .unavailable(.unavailable)
            )
        }
    }
}

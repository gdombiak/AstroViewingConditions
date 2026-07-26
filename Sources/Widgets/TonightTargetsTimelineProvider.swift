import SharedCode
import WidgetKit

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

        guard let summary = await AppGroupStorage.loadWidgetTonightTargetsSummaryAsync() else {
            return TonightTargetsEntry(
                date: referenceDate,
                state: .unavailable(.noCache)
            )
        }

        guard summary.locationMatches(location) else {
            return TonightTargetsEntry(
                date: referenceDate,
                state: .unavailable(.locationMismatch)
            )
        }

        guard summary.matchesCurrentObservingNight(relativeTo: referenceDate) else {
            return TonightTargetsEntry(
                date: referenceDate,
                state: .unavailable(.observingNightMismatch)
            )
        }

        guard summary.isWithinMaximumAge(
            Self.payloadMaximumAge,
            relativeTo: referenceDate
        ) else {
            return TonightTargetsEntry(
                date: referenceDate,
                state: .unavailable(.stale)
            )
        }

        switch summary.status {
        case .available where !summary.targets.isEmpty:
            return TonightTargetsEntry(date: referenceDate, state: .available(summary))
        case .noTargets:
            return TonightTargetsEntry(date: referenceDate, state: .noTargets)
        case .unavailable, .available:
            return TonightTargetsEntry(
                date: referenceDate,
                state: .unavailable(.unavailable)
            )
        }
    }
}

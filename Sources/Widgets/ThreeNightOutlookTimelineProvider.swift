import SharedCode
import WidgetKit

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
        guard let summary = await AppGroupStorage.loadWidgetThreeNightOutlookSummaryAsync() else {
            return .init(date: referenceDate, state: .unavailable(.noCache))
        }
        switch ThreeNightOutlookEntryResolver.resolve(
            summary: summary, selectedLocation: location, referenceDate: referenceDate,
            maximumAge: Self.payloadMaximumAge
        ) {
        case .available:
            return .init(date: referenceDate, state: .available(summary))
        case .noLocation:
            return .init(date: referenceDate, state: .unavailable(.noLocation))
        case .noCache:
            return .init(date: referenceDate, state: .unavailable(.noCache))
        case .stale:
            return .init(date: referenceDate, state: .unavailable(.stale))
        case .locationMismatch:
            return .init(date: referenceDate, state: .unavailable(.locationMismatch))
        case .observingNightMismatch:
            return .init(date: referenceDate, state: .unavailable(.observingNightMismatch))
        case .unavailable:
            return .init(date: referenceDate, state: .unavailable(.unavailable))
        }
    }
}

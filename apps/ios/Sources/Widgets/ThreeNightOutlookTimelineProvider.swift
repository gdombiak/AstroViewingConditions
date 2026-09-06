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
            outlookWidgetLogger.error(
                "ThreeNight unavailable reason=noLocation stage=location cache=missing path=noCache"
            )
            return .init(date: referenceDate, state: .unavailable(.noLocation))
        }
        outlookWidgetLogger.info("Selected location: \(location.name, privacy: .public)")
        let cachedSummary = await AppGroupStorage.loadWidgetThreeNightOutlookSummaryAsync()
        let cachedLocation = CachedLocation(
            id: location.source == .saved ? location.id : nil,
            name: location.name, latitude: location.latitude, longitude: location.longitude
        )
        let repository = SharedConditionsRepository()
        return await ThreeNightOutlookEntryResolver.buildEntry(
            location: location,
            cachedSummary: cachedSummary,
            cachedLocation: cachedLocation,
            referenceDate: referenceDate,
            normalConditions: {
                let result = try await repository.conditions(
                    for: cachedLocation,
                    referenceDate: referenceDate
                )
                outlookWidgetLogger.info(
                    "Conditions returned; fetchedAt: \(result.conditions.fetchedAt.description, privacy: .public)"
                )
                return result.conditions
            },
            retainedConditions: {
                await repository.matchingCachedConditions(for: cachedLocation)
            },
            save: { summary in
                await AppGroupStorage.saveWidgetThreeNightOutlookSummaryAsync(summary)
                outlookWidgetLogger.info("Rebuilt and saved Three-Night Outlook summary")
            },
            postWorkValidationDate: Date.init,
            logUnavailable: { context in
                outlookWidgetLogger.error(
                    "\(unavailableLogLine(context), privacy: .public)"
                )
            }
        )
    }

}

private func unavailableLogLine(
    _ context: ThreeNightOutlookUnavailableLogContext
) -> String {
    var fields = [
        "ThreeNight unavailable",
        "reason=\(unavailableReasonName(context.reason))",
        "stage=\(context.stage)",
        "cache=\(context.cache)",
        "path=\(context.path)"
    ]
    if let age = context.age {
        fields.append("age=\(Int(age.rounded()))")
    }
    if let maximumAge = context.maximumAge {
        fields.append("maxAge=\(Int(maximumAge))")
    }
    if let category = context.fetchFailureCategory {
        fields.append("fetch=\(category)")
    }
    if let observingDate = context.cachedObservingDate {
        fields.append("cachedNight=\(observingDate.timeIntervalSince1970)")
    }
    return fields.joined(separator: " ")
}

private func unavailableReasonName(
    _ reason: ThreeNightOutlookEntry.UnavailableReason
) -> String {
    switch reason {
    case .noLocation: "noLocation"
    case .noCache: "noCache"
    case .stale: "stale"
    case .locationMismatch: "locationMismatch"
    case .observingNightMismatch: "observingNightMismatch"
    case .unavailable: "unavailable"
    }
}

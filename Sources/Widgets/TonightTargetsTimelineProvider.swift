import SharedCode
import WidgetKit
import os

private let targetsWidgetLogger = Logger(subsystem: "com.astroviewing.conditions.widget", category: "TonightTargets")

struct TonightTargetsTimelineProvider: TimelineProvider {
    static let timelineReevaluationInterval: TimeInterval = 3600

    func placeholder(in context: Context) -> TonightTargetsEntry {
        .placeholder
    }

    func getSnapshot(
        in context: Context,
        completion: @Sendable @escaping (TonightTargetsEntry) -> Void
    ) {
        guard !context.isPreview else {
            completion(.placeholder)
            return
        }
        Task { @Sendable in
            completion(await buildEntry())
        }
    }

    func getTimeline(
        in context: Context,
        completion: @Sendable @escaping (Timeline<TonightTargetsEntry>) -> Void
    ) {
        Task { @Sendable in
            let referenceDate = Date()
            targetsWidgetLogger.info("Timeline invocation")
            let entry = await buildEntry(referenceDate: referenceDate)
            let nextRequestDate = referenceDate.addingTimeInterval(
                Self.timelineReevaluationInterval
            )
            targetsWidgetLogger.info(
                "Next timeline request: \(nextRequestDate.description, privacy: .public)"
            )
            completion(Timeline(
                entries: [entry],
                policy: .after(nextRequestDate)
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
        targetsWidgetLogger.info("Selected location: \(location.name, privacy: .public)")

        let cachedSummary = await AppGroupStorage.loadWidgetTonightTargetsSummaryAsync()
        let cachedLocation = CachedLocation(
            id: location.source == .saved ? location.id : nil,
            name: location.name, latitude: location.latitude, longitude: location.longitude
        )
        do {
            let conditions = try await WidgetConditionsRefreshService().conditions(
                for: cachedLocation, referenceDate: referenceDate
            )
            targetsWidgetLogger.info(
                "Conditions returned; fetchedAt: \(conditions.fetchedAt.description, privacy: .public)"
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
                targetsWidgetLogger.info("Rebuilt and saved Tonight’s Targets summary")
                return entry(for: summary, date: referenceDate)
            case .preserveExisting:
                if let cachedSummary {
                    targetsWidgetLogger.info("Preserving active previous-night Targets summary")
                    return entry(for: cachedSummary, date: referenceDate)
                }
            case .unavailable:
                let summary = TonightTargetsWidgetPayloadBuilder.makeUnavailableSummary(
                    generatedAt: conditions.fetchedAt, location: conditions.location,
                    timeZone: conditions.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
                        ?? LocationTimeZoneResolver.approximate(longitude: conditions.location.longitude),
                    referenceDate: referenceDate
                )
                await AppGroupStorage.saveWidgetTonightTargetsSummaryAsync(summary)
                targetsWidgetLogger.info("Rebuilt and saved unavailable Targets summary")
                return entry(for: summary, date: referenceDate)
            }
        } catch {
            targetsWidgetLogger.warning(
                "Conditions service failed: \(error.localizedDescription, privacy: .public)"
            )
        }

        if let cachedSummary,
           cachedSummary.locationMatches(location),
           cachedSummary.matchesCurrentObservingNight(relativeTo: referenceDate) {
            targetsWidgetLogger.info("Using matching last-known-good Targets summary")
            return entry(for: cachedSummary, date: referenceDate)
        }
        targetsWidgetLogger.warning("No usable Targets summary fallback")
        return .init(date: referenceDate, state: .unavailable(cachedSummary == nil ? .noCache : .stale))
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

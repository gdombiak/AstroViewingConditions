import Foundation
import SharedCode

enum ThreeNightOutlookResolvedState: Equatable {
    case available
    case noLocation
    case noCache
    case stale
    case locationMismatch
    case observingNightMismatch
    case unavailable
}

/// Pure validation used by the cache-loading timeline provider and its tests.
enum ThreeNightOutlookEntryResolver {
    static func resolve(
        summary: WidgetThreeNightOutlookSummary?,
        selectedLocation: SelectedLocation?,
        referenceDate: Date,
        maximumAge: TimeInterval = WidgetThreeNightOutlookSummary.maximumAge
    ) -> ThreeNightOutlookResolvedState {
        guard let selectedLocation else { return .noLocation }
        guard let summary else { return .noCache }
        guard summary.locationMatches(selectedLocation) else { return .locationMismatch }
        guard summary.isWithinMaximumAge(
            maximumAge,
            relativeTo: referenceDate
        ) else { return .stale }
        guard summary.status == .available else { return .unavailable }
        guard summary.hasCorrectlyOrderedNights(),
              summary.nights.allSatisfy({
                  $0.status != .available || $0.score != nil
              }) else { return .unavailable }
        guard summary.matchesCurrentObservingNight(relativeTo: referenceDate) else {
            return .observingNightMismatch
        }
        return .available
    }

    static func failedRefreshEntry(
        cachedSummary: WidgetThreeNightOutlookSummary?,
        selectedLocation: SelectedLocation,
        referenceDate: Date
    ) -> ThreeNightOutlookEntry {
        if resolve(
            summary: cachedSummary,
            selectedLocation: selectedLocation,
            referenceDate: referenceDate
        ) == .available,
           let cachedSummary {
            return .init(
                date: referenceDate,
                state: .available(cachedSummary),
                dataStatus: .fallback(summary: cachedSummary)
            )
        }
        return .init(
            date: referenceDate,
            state: .unavailable(cachedSummary == nil ? .noCache : .stale)
        )
    }

    static func buildEntry(
        location: SelectedLocation,
        cachedSummary: WidgetThreeNightOutlookSummary?,
        cachedLocation: CachedLocation,
        referenceDate: Date,
        normalConditions: () async throws -> ViewingConditions,
        retainedConditions: () async -> ViewingConditions?,
        save: (WidgetThreeNightOutlookSummary) async -> Void
    ) async -> ThreeNightOutlookEntry {
        do {
            let conditions = try await normalConditions()
            let decision = ThreeNightOutlookWidgetPayloadBuilder.publicationDecision(
                conditions: conditions,
                existingSummary: cachedSummary,
                referenceDate: referenceDate,
                timeZone: conditions.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            )
            return await entry(
                for: decision,
                cachedSummary: cachedSummary,
                location: location,
                referenceDate: referenceDate,
                dataStatus: .normal(conditions: conditions),
                save: save
            )
        } catch {
            if let retained = await retainedConditions(),
               conditionsLocationMatches(retained, cachedLocation: cachedLocation) {
                let decision = ThreeNightOutlookWidgetPayloadBuilder.publicationDecision(
                    conditions: retained,
                    existingSummary: cachedSummary,
                    referenceDate: referenceDate,
                    timeZone: retained.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
                )
                if case let .publish(summary) = decision, summary.isDataBearing {
                    await save(summary)
                    return .init(
                        date: referenceDate,
                        state: .available(summary),
                        dataStatus: .fallback(conditions: retained)
                    )
                }
            }
            return failedRefreshEntry(
                cachedSummary: cachedSummary,
                selectedLocation: location,
                referenceDate: referenceDate
            )
        }
    }

    private static func entry(
        for decision: ThreeNightOutlookPublicationDecision,
        cachedSummary: WidgetThreeNightOutlookSummary?,
        location: SelectedLocation,
        referenceDate: Date,
        dataStatus: WidgetDataStatus,
        save: (WidgetThreeNightOutlookSummary) async -> Void
    ) async -> ThreeNightOutlookEntry {
        switch decision {
        case let .publish(summary):
            if summary.isDataBearing { await save(summary) }
            return availableEntry(
                summary: summary,
                location: location,
                referenceDate: referenceDate,
                dataStatus: dataStatus
            )
        case .preserveExisting:
            if let cachedSummary {
                return availableEntry(
                    summary: cachedSummary,
                    location: location,
                    referenceDate: referenceDate,
                    dataStatus: .normal(summary: cachedSummary)
                )
            }
        case let .unavailable(summary):
            if cachedSummary?.isDataBearing == true,
               resolve(
                summary: cachedSummary,
                selectedLocation: location,
                referenceDate: referenceDate
               ) == .available,
               let cachedSummary {
                return .init(
                    date: referenceDate,
                    state: .available(cachedSummary),
                    dataStatus: .fallback(summary: cachedSummary)
                )
            }
            if cachedSummary?.isDataBearing != true { await save(summary) }
            return availableEntry(
                summary: summary,
                location: location,
                referenceDate: referenceDate,
                dataStatus: dataStatus
            )
        }
        return .init(date: referenceDate, state: .unavailable(.noCache))
    }

    private static func availableEntry(
        summary: WidgetThreeNightOutlookSummary,
        location: SelectedLocation,
        referenceDate: Date,
        dataStatus: WidgetDataStatus
    ) -> ThreeNightOutlookEntry {
        switch resolve(summary: summary, selectedLocation: location, referenceDate: referenceDate) {
        case .available:
            return .init(
                date: referenceDate,
                state: .available(summary),
                dataStatus: dataStatus
            )
        case .noLocation: return .init(date: referenceDate, state: .unavailable(.noLocation))
        case .noCache: return .init(date: referenceDate, state: .unavailable(.noCache))
        case .stale: return .init(date: referenceDate, state: .unavailable(.stale))
        case .locationMismatch: return .init(date: referenceDate, state: .unavailable(.locationMismatch))
        case .observingNightMismatch: return .init(date: referenceDate, state: .unavailable(.observingNightMismatch))
        case .unavailable: return .init(date: referenceDate, state: .unavailable(.unavailable))
        }
    }

    private static func conditionsLocationMatches(
        _ conditions: ViewingConditions,
        cachedLocation: CachedLocation
    ) -> Bool {
        WidgetLocationIdentity.matches(
            summarySavedLocationID: conditions.location.id,
            selectedSavedLocationID: cachedLocation.id,
            summaryLatitude: conditions.location.latitude,
            summaryLongitude: conditions.location.longitude,
            selectedLatitude: cachedLocation.latitude,
            selectedLongitude: cachedLocation.longitude
        )
    }
}

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

struct ThreeNightOutlookUnavailableLogContext: Equatable {
    let reason: ThreeNightOutlookEntry.UnavailableReason
    let stage: String
    let cache: String
    let age: TimeInterval?
    let maximumAge: TimeInterval?
    let path: String
    let fetchFailureCategory: String?
    let cachedObservingDate: Date?
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
        referenceDate: Date,
        fetchFailureCategory: String? = nil,
        logUnavailable: (ThreeNightOutlookUnavailableLogContext) -> Void = { _ in }
    ) -> ThreeNightOutlookEntry {
        if let cachedSummary,
           ThreeNightOutlookPersistencePolicy.isValidLastKnownGood(
            cachedSummary,
            for: cachedLocation(from: selectedLocation),
            referenceDate: referenceDate
        ) {
            return .init(
                date: referenceDate,
                state: .available(cachedSummary),
                dataStatus: .fallback(summary: cachedSummary)
            )
        }
        let reason: ThreeNightOutlookEntry.UnavailableReason =
            cachedSummary == nil ? .noCache : .stale
        logUnavailable(.init(
            reason: reason,
            stage: fallbackStage(
                summary: cachedSummary,
                selectedLocation: selectedLocation,
                referenceDate: referenceDate
            ),
            cache: cachedSummary == nil ? "missing" : "loaded",
            age: cachedSummary.map { referenceDate.timeIntervalSince($0.generatedAt) },
            maximumAge: ThreeNightOutlookPersistencePolicy.lastKnownGoodMaximumAge,
            path: cachedSummary == nil ? "noCache" : "rejectedCache",
            fetchFailureCategory: fetchFailureCategory,
            cachedObservingDate: cachedSummary?.nights.first?.observingDate
        ))
        return .init(
            date: referenceDate,
            state: .unavailable(reason)
        )
    }

    static func buildEntry(
        location: SelectedLocation,
        cachedSummary: WidgetThreeNightOutlookSummary?,
        cachedLocation: CachedLocation,
        referenceDate: Date,
        normalConditions: () async throws -> ViewingConditions,
        retainedConditions: () async -> ViewingConditions?,
        save: (WidgetThreeNightOutlookSummary) async -> Void,
        postWorkValidationDate: (() -> Date)? = nil,
        logUnavailable: (ThreeNightOutlookUnavailableLogContext) -> Void = { _ in }
    ) async -> ThreeNightOutlookEntry {
        let validationDate = {
            postWorkValidationDate?() ?? referenceDate
        }
        do {
            let conditions = try await normalConditions()
            let locationContext = CrossSurfaceLocationContext.make(from: location)
            let decision = ThreeNightOutlookWidgetPayloadBuilder.publicationDecision(
                conditions: conditions,
                existingSummary: cachedSummary,
                referenceDate: referenceDate,
                timeZone: conditions.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)),
                locationContext: locationContext
            )
            let validationDate = validationDate()
            return await entry(
                for: decision,
                cachedSummary: cachedSummary,
                location: location,
                validationDate: validationDate,
                dataStatus: .normal(conditions: conditions),
                save: save,
                logUnavailable: logUnavailable
            )
        } catch {
            let fetchFailureCategory = sanitizedErrorCategory(error)
            if let retained = await retainedConditions(),
               conditionsLocationMatches(retained, cachedLocation: cachedLocation) {
                let locationContext = CrossSurfaceLocationContext.make(from: location)
                let decision = ThreeNightOutlookWidgetPayloadBuilder.publicationDecision(
                    conditions: retained,
                    existingSummary: cachedSummary,
                    referenceDate: referenceDate,
                    timeZone: retained.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)),
                    locationContext: locationContext
                )
                let validationDate = validationDate()
                if case let .publish(summary) = decision, summary.isDataBearing {
                    await save(summary)
                    return availableEntry(
                        summary: summary,
                        location: location,
                        validationDate: validationDate,
                        dataStatus: .fallback(conditions: retained),
                        cachedSummary: cachedSummary,
                        path: "retained",
                        fetchFailureCategory: fetchFailureCategory,
                        logUnavailable: logUnavailable
                    )
                }
                return failedRefreshEntry(
                    cachedSummary: cachedSummary,
                    selectedLocation: location,
                    referenceDate: validationDate,
                    fetchFailureCategory: fetchFailureCategory,
                    logUnavailable: logUnavailable
                )
            }
            let validationDate = validationDate()
            return failedRefreshEntry(
                cachedSummary: cachedSummary,
                selectedLocation: location,
                referenceDate: validationDate,
                fetchFailureCategory: fetchFailureCategory,
                logUnavailable: logUnavailable
            )
        }
    }

    private static func entry(
        for decision: ThreeNightOutlookPublicationDecision,
        cachedSummary: WidgetThreeNightOutlookSummary?,
        location: SelectedLocation,
        validationDate: Date,
        dataStatus: WidgetDataStatus,
        save: (WidgetThreeNightOutlookSummary) async -> Void,
        logUnavailable: (ThreeNightOutlookUnavailableLogContext) -> Void
    ) async -> ThreeNightOutlookEntry {
        switch decision {
        case let .publish(summary):
            if summary.isDataBearing { await save(summary) }
            return availableEntry(
                summary: summary,
                location: location,
                validationDate: validationDate,
                dataStatus: dataStatus,
                cachedSummary: cachedSummary,
                path: "new",
                logUnavailable: logUnavailable
            )
        case .preserveExisting:
            if let cachedSummary {
                return availableEntry(
                    summary: cachedSummary,
                    location: location,
                    validationDate: validationDate,
                    dataStatus: .normal(summary: cachedSummary),
                    cachedSummary: cachedSummary,
                    path: "preserved",
                    logUnavailable: logUnavailable
                )
            }
        case let .unavailable(summary):
            if let cachedSummary,
               ThreeNightOutlookPersistencePolicy.isValidLastKnownGood(
                cachedSummary,
                for: cachedLocation(from: location),
                referenceDate: validationDate
               ) {
                return .init(
                    date: validationDate,
                    state: .available(cachedSummary),
                    dataStatus: .fallback(summary: cachedSummary)
                )
            }
            if cachedSummary?.isDataBearing != true { await save(summary) }
            return availableEntry(
                summary: summary,
                location: location,
                validationDate: validationDate,
                dataStatus: dataStatus,
                cachedSummary: cachedSummary,
                path: "unavailable",
                logUnavailable: logUnavailable
            )
        }
        logUnavailable(.init(
            reason: .noCache,
            stage: "cache",
            cache: "missing",
            age: nil,
            maximumAge: nil,
            path: "noCache",
            fetchFailureCategory: nil,
            cachedObservingDate: nil
        ))
        return .init(date: validationDate, state: .unavailable(.noCache))
    }

    private static func availableEntry(
        summary: WidgetThreeNightOutlookSummary,
        location: SelectedLocation,
        validationDate: Date,
        dataStatus: WidgetDataStatus,
        cachedSummary: WidgetThreeNightOutlookSummary?,
        path: String,
        fetchFailureCategory: String? = nil,
        logUnavailable: (ThreeNightOutlookUnavailableLogContext) -> Void
    ) -> ThreeNightOutlookEntry {
        let resolved = resolve(
            summary: summary,
            selectedLocation: location,
            referenceDate: validationDate
        )
        switch resolved {
        case .available:
            return .init(
                date: validationDate,
                state: .available(summary),
                dataStatus: dataStatus
            )
        case .noLocation, .noCache, .stale, .locationMismatch,
             .observingNightMismatch, .unavailable:
            let reason = unavailableReason(for: resolved)
            logUnavailable(.init(
                reason: reason,
                stage: validationStage(for: resolved, summary: summary),
                cache: cachedSummary == nil ? "missing" : "loaded",
                age: validationDate.timeIntervalSince(summary.generatedAt),
                maximumAge: WidgetThreeNightOutlookSummary.maximumAge,
                path: path,
                fetchFailureCategory: fetchFailureCategory,
                cachedObservingDate: summary.nights.first?.observingDate
            ))
            return .init(date: validationDate, state: .unavailable(reason))
        }
    }

    private static func unavailableReason(
        for state: ThreeNightOutlookResolvedState
    ) -> ThreeNightOutlookEntry.UnavailableReason {
        switch state {
        case .noLocation: .noLocation
        case .noCache: .noCache
        case .stale: .stale
        case .locationMismatch: .locationMismatch
        case .observingNightMismatch: .observingNightMismatch
        case .unavailable, .available: .unavailable
        }
    }

    private static func validationStage(
        for state: ThreeNightOutlookResolvedState,
        summary: WidgetThreeNightOutlookSummary
    ) -> String {
        switch state {
        case .stale: "presentationAge"
        case .locationMismatch, .noLocation: "location"
        case .observingNightMismatch: "observingNight"
        case .unavailable: summary.status == .available ? "structure" : "status"
        case .noCache: "cache"
        case .available: "status"
        }
    }

    private static func fallbackStage(
        summary: WidgetThreeNightOutlookSummary?,
        selectedLocation: SelectedLocation,
        referenceDate: Date
    ) -> String {
        guard let summary else { return "cache" }
        guard summary.locationMatches(selectedLocation) else { return "location" }
        guard summary.status == .available, summary.isDataBearing else { return "status" }
        guard summary.hasCorrectlyOrderedNights(),
              summary.nights.allSatisfy({
                  $0.status != .available || $0.score != nil
              }) else { return "structure" }
        guard summary.isWithinMaximumAge(
            ThreeNightOutlookPersistencePolicy.lastKnownGoodMaximumAge,
            relativeTo: referenceDate
        ) else { return "fallbackAge" }
        guard summary.matchesCurrentObservingNight(relativeTo: referenceDate) else {
            return "observingNight"
        }
        return "status"
    }

    private static func sanitizedErrorCategory(_ error: Error) -> String {
        if let urlError = error as? URLError {
            return "url-\(urlError.code.rawValue)"
        }
        return String(describing: type(of: error))
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

    private static func cachedLocation(from selectedLocation: SelectedLocation) -> CachedLocation {
        CachedLocation(
            id: selectedLocation.source == .saved ? selectedLocation.id : nil,
            name: selectedLocation.name,
            latitude: selectedLocation.latitude,
            longitude: selectedLocation.longitude
        )
    }
}

import Foundation
import AstroEngine

// MARK: - Companion display policy (read-only complications)

/// Accepted companion inputs for a live complication timeline entry.
public struct WatchComplicationCompanionDisplayContext: Sendable {
    public let selected: SelectedLocation
    public let conditions: ViewingConditions
    /// Tonight context from ``ActiveObservingNightResolver`` (single cross-midnight authority).
    public let activeNight: TargetRecommendationContextResolution

    public init(
        selected: SelectedLocation,
        conditions: ViewingConditions,
        activeNight: TargetRecommendationContextResolution
    ) {
        self.selected = selected
        self.conditions = conditions
        self.activeNight = activeNight
    }
}

/// Freshness and association gate for watch Night Conditions complications.
///
/// Complications are **companion-only**: they re-read the App Group conditions + OQ pair
/// written by the watch app / connectivity path and never fetch weather themselves.
public enum WatchComplicationCompanionDisplayPolicy: Sendable {
    /// Last-known-good max age when *displaying* a coherent companion pair.
    ///
    /// Age only — not a calendar-day cut. Calendar midnight would hide a pair still inside
    /// the active astronomical night (e.g. Sunday 22:00 fetch at Monday 01:00).
    ///
    /// Combined with ``ActiveObservingNightResolver`` so we only show data that can still
    /// resolve Tonight. Intentionally **not** ``WatchConditionsPushAcceptance/freshConditionsInterval``
    /// (1 hour): that gate is for push/refresh authority. A 24-hour bound matches the iOS
    /// Night Conditions widget last-known-good fallback window.
    public static let companionDisplayMaxAge: TimeInterval = 24 * 3600

    public enum RejectionReason: String, Sendable, Equatable, Error {
        case noSelectedLocation
        case noConditions
        case locationMismatch
        /// Older than ``companionDisplayMaxAge``.
        case stale
        /// Payload cannot resolve Tonight via ``ActiveObservingNightResolver``
        /// (ended night without usable next context, missing astronomy days, etc.).
        case inactiveObservingNight
    }

    /// Whether the companion pair may be shown for the selected location at `referenceDate`.
    ///
    /// Rules:
    /// 1. Selected location + conditions present and location-associated
    /// 2. `conditions.fetchedAt` within ``companionDisplayMaxAge`` (wall-clock age)
    /// 3. ``ActiveObservingNightResolver`` returns `.resolved` for these conditions
    ///    (survives local midnight while still inside the active astronomical night;
    ///    becomes unavailable when Tonight can no longer be resolved from the payload)
    public static func evaluate(
        selectedLocation: SelectedLocation?,
        conditions: ViewingConditions?,
        referenceDate: Date = Date()
    ) -> Result<WatchComplicationCompanionDisplayContext, RejectionReason> {
        guard let selectedLocation else {
            return .failure(.noSelectedLocation)
        }
        guard let conditions else {
            return .failure(.noConditions)
        }
        guard conditions.locationMatches(
            latitude: selectedLocation.latitude,
            longitude: selectedLocation.longitude
        ) else {
            return .failure(.locationMismatch)
        }
        guard conditions.isFresh(
            within: companionDisplayMaxAge,
            relativeTo: referenceDate
        ) else {
            return .failure(.stale)
        }

        let timeZone = conditions.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
        switch ActiveObservingNightResolver.resolve(
            conditions: conditions,
            referenceDate: referenceDate,
            timeZone: timeZone
        ) {
        case let .resolved(activeNight):
            return .success(
                WatchComplicationCompanionDisplayContext(
                    selected: selectedLocation,
                    conditions: conditions,
                    activeNight: activeNight
                )
            )
        case .requiresActivePreviousPayload, .unavailable:
            // Companion has no separate prior-night summary to preserve (unlike iOS
            // Tonight Targets); without a resolved Tonight from this payload, hide.
            return .failure(.inactiveObservingNight)
        }
    }
}

// MARK: - Headline resolution

/// Resolves complication headline from night score + optional associated OQ document.
public enum WatchComplicationHeadlineResolver: Sendable {
    /// - Parameter nightScore: Night Conditions score for the **active observing night**
    ///   (from ``ActiveObservingNightResolver`` / display policy). Must match the score the
    ///   OQ document was associated with — do not re-derive via calendar dayOffset 0 alone.
    public static func resolve(
        conditions: ViewingConditions,
        document: WatchObservingQualityDocument?,
        selectedLocation: SelectedLocation?,
        nightScore: Int
    ) -> (score: Int, presentationMode: WatchHeadlineScorePresentationMode) {
        guard let document else {
            return (nightScore, .nightConditionsFallback)
        }
        // Pass the active-night score into association/recompute so local midnight does not
        // rebind association to calendar-day `analyzeConditions(dayOffset: 0)`.
        let outcome = WatchObservingQualityCanonicalizer.resolvePersisted(
            document: document,
            conditions: conditions,
            selectedLocation: selectedLocation,
            nightConditionsScore: nightScore
        )
        switch outcome {
        case let .enhanced(snapshot, _):
            let mode = WatchHeadlineScorePresentationMode.from(
                brightnessAvailability: snapshot.brightnessAvailability
            )
            switch mode {
            case .observingQuality:
                return (snapshot.observingQualityScore, .observingQuality)
            case .nightConditionsFallback:
                return (nightScore, .nightConditionsFallback)
            }
        case .nightOnly:
            return (nightScore, .nightConditionsFallback)
        }
    }
}

// MARK: - Unavailable presentation

/// Compact copy for live complication timelines when companion state is missing/stale.
///
/// Not used for WidgetKit gallery placeholder (synthetic example scores stay separate).
public enum WatchComplicationUnavailablePresentation: Sendable {
    public static let scoreText = "--"
    public static let title = "Night Conditions"
    public static let detail = "Unavailable"
    public static let accessibilityLabel = "Night conditions unavailable"
}

import Foundation

/// Whether the existing Watch conditions refresh path should run.
///
/// This is **not** a second acquisition/scoring pipeline. It only decides whether
/// ``WatchConditionsManager`` should invoke its existing `performRefresh` for a
/// previously resolved selected location.
public enum WatchBackgroundRefreshDecision: Sendable, Equatable {
    case skip(SkipReason)
    /// Refresh **this** selected location — callers must not re-read selection after decide.
    case refresh(SelectedLocation)

    public enum SkipReason: String, Sendable, Equatable {
        case noSelectedLocation
        case stillFreshAndDisplayable
    }

    public var selectedLocation: SelectedLocation? {
        if case let .refresh(location) = self { return location }
        return nil
    }
}

/// Shared refresh gate used by the Watch dashboard and Watch-app background entry points.
public enum WatchBackgroundRefreshPolicy: Sendable {
    /// Resolve whether the existing refresh path should run for `selectedLocation`.
    ///
    /// Refresh when any of:
    /// - no conditions
    /// - conditions are not associated with `selectedLocation`
    /// - conditions fail the 1-hour / same-local-day Watch refresh gate
    /// - the read-only complication display policy would show `--`
    public static func decide(
        selectedLocation: SelectedLocation?,
        conditions: ViewingConditions?,
        referenceDate: Date = Date()
    ) -> WatchBackgroundRefreshDecision {
        guard let selectedLocation else {
            return .skip(.noSelectedLocation)
        }

        guard let conditions else {
            return .refresh(selectedLocation)
        }

        if !WatchConditionsPushAcceptance.conditionsMatch(conditions, selected: selectedLocation) {
            return .refresh(selectedLocation)
        }

        if !conditions.isFreshForLocalDay(
            within: WatchConditionsPushAcceptance.freshConditionsInterval,
            relativeTo: referenceDate
        ) {
            return .refresh(selectedLocation)
        }

        if case .failure = WatchComplicationCompanionDisplayPolicy.evaluate(
            selectedLocation: selectedLocation,
            conditions: conditions,
            referenceDate: referenceDate
        ) {
            return .refresh(selectedLocation)
        }

        return .skip(.stillFreshAndDisplayable)
    }

    /// Weather (and optional brightness) must belong to the same selected location
    /// that `decide` already bound. Brightness may be absent (night-only fallback).
    public static func inputsMatchSelectedLocation(
        selectedLocation: SelectedLocation,
        conditions: ViewingConditions,
        brightnessSample: ModeledZenithBrightnessSample?
    ) -> Bool {
        guard WatchConditionsPushAcceptance.conditionsMatch(
            conditions,
            selected: selectedLocation
        ) else {
            return false
        }
        guard let brightnessSample else { return true }
        return brightnessSampleMatches(brightnessSample, selected: selectedLocation)
    }

    private static func brightnessSampleMatches(
        _ sample: ModeledZenithBrightnessSample,
        selected: SelectedLocation
    ) -> Bool {
        switch selected.source {
        case .saved:
            guard let selectedID = selected.id,
                  sample.savedLocationID == selectedID else {
                return false
            }
            return ModeledZenithBrightnessValidity.coordinatesMatch(
                sampleLatitude: sample.latitude,
                sampleLongitude: sample.longitude,
                requestLatitude: selected.latitude,
                requestLongitude: selected.longitude
            )
        case .currentGPS:
            guard sample.savedLocationID == nil else { return false }
            if selected.latitude == 0, selected.longitude == 0 {
                return true
            }
            return ModeledZenithBrightnessValidity.coordinatesMatch(
                sampleLatitude: sample.latitude,
                sampleLongitude: sample.longitude,
                requestLatitude: selected.latitude,
                requestLongitude: selected.longitude
            )
        }
    }
}

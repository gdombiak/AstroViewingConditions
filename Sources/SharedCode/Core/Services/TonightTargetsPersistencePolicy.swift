import Foundation

/// Shared retention rules for the Tonight's Targets app cache and widget fallback.
public enum TonightTargetsPersistencePolicy {
    public static func shouldSave(
        candidate: WidgetTonightTargetsSummary,
        existing: WidgetTonightTargetsSummary?,
        targetLocation: CachedLocation,
        referenceDate: Date
    ) -> Bool {
        guard candidate.locationMatches(targetLocation),
              candidate.matchesCurrentObservingNight(relativeTo: referenceDate)
        else { return false }

        switch candidate.status {
        case .available:
            return !candidate.targets.isEmpty
        case .noTargets:
            return true
        case .unavailable:
            return !isValidLastKnownGood(
                existing,
                for: targetLocation,
                referenceDate: referenceDate
            )
        }
    }

    /// A retained Targets summary must be data-bearing (or explicitly say
    /// there are no targets), match the selected location, describe the
    /// active observing night, and remain within the shared cache-age bound.
    public static func isValidLastKnownGood(
        _ summary: WidgetTonightTargetsSummary?,
        for targetLocation: CachedLocation,
        referenceDate: Date
    ) -> Bool {
        guard let summary,
              summary.locationMatches(targetLocation),
              summary.matchesCurrentObservingNight(relativeTo: referenceDate),
              summary.isWithinMaximumAge(
                  WidgetTonightTargetsSummary.maximumAge,
                  relativeTo: referenceDate
              )
        else { return false }

        switch summary.status {
        case .available:
            return !summary.targets.isEmpty
        case .noTargets:
            return true
        case .unavailable:
            return false
        }
    }
}

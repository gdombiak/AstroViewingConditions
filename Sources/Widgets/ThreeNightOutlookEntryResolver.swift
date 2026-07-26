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
}

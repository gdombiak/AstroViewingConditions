import Foundation

/// Shared retention rules for the Three-Night Outlook's app cache and widget fallback.
public enum ThreeNightOutlookPersistencePolicy {
    public static let lastKnownGoodMaximumAge: TimeInterval = 24 * 60 * 60

    public static func isStructurallyUseful(
        _ summary: WidgetThreeNightOutlookSummary?,
        for targetLocation: CachedLocation
    ) -> Bool {
        guard let summary else { return false }
        return summary.isDataBearing
            && summary.status == .available
            && summary.locationMatches(targetLocation)
            && summary.hasCorrectlyOrderedNights()
            && summary.nights.allSatisfy {
                $0.status != .available || $0.score != nil
            }
    }

    /// A bounded widget fallback must also describe the active observing night.
    public static func isValidLastKnownGood(
        _ summary: WidgetThreeNightOutlookSummary?,
        for targetLocation: CachedLocation,
        referenceDate: Date
    ) -> Bool {
        guard let summary else { return false }
        return isStructurallyUseful(summary, for: targetLocation)
            && summary.isWithinMaximumAge(
                lastKnownGoodMaximumAge,
                relativeTo: referenceDate
            )
            && summary.matchesCurrentObservingNight(relativeTo: referenceDate)
    }

    public static func shouldSave(
        decision: ThreeNightOutlookPublicationDecision,
        existing: WidgetThreeNightOutlookSummary?,
        targetLocation: CachedLocation,
        referenceDate: Date
    ) -> Bool {
        switch decision {
        case let .publish(summary):
            return summary.isDataBearing
                || !isUsefulExistingSummary(
                    existing,
                    for: targetLocation,
                    referenceDate: referenceDate
                )
        case .unavailable:
            return shouldSaveUnavailable(
                existing: existing,
                targetLocation: targetLocation,
                referenceDate: referenceDate
            )
        case .preserveExisting:
            return false
        }
    }

    public static func shouldSaveUnavailable(
        existing: WidgetThreeNightOutlookSummary?,
        targetLocation: CachedLocation,
        referenceDate: Date
    ) -> Bool {
        !isUsefulExistingSummary(
            existing,
            for: targetLocation,
            referenceDate: referenceDate
        )
    }

    private static func isUsefulExistingSummary(
        _ summary: WidgetThreeNightOutlookSummary?,
        for targetLocation: CachedLocation,
        referenceDate: Date
    ) -> Bool {
        guard let summary else { return false }
        return isStructurallyUseful(summary, for: targetLocation)
            && summary.isWithinMaximumAge(
                lastKnownGoodMaximumAge,
                relativeTo: referenceDate
            )
    }
}

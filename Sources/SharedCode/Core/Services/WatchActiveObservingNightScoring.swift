import Foundation

/// Shared “which night is Tonight?” scoring for watch accept / local refresh.
///
/// Uses ``ActiveObservingNightResolver`` as the sole Tonight authority (same as complications).
public enum WatchActiveObservingNightScoring: Sendable {
    /// Night quality for the active observing night, or calendar `analyzeConditions` if
    /// ActiveObservingNight cannot resolve (unavailable / requires previous payload missing).
    public static func nightQuality(
        conditions: ViewingConditions,
        referenceDate: Date = Date(),
        timeZone: TimeZone? = nil
    ) -> NightQualityAssessment? {
        let tz = timeZone
            ?? conditions.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
        switch ActiveObservingNightResolver.resolve(
            conditions: conditions,
            referenceDate: referenceDate,
            timeZone: tz
        ) {
        case let .resolved(resolution):
            return resolution.context.nightQuality
        case .requiresActivePreviousPayload, .unavailable:
            return NightQualityAnalyzer.analyzeConditions(
                conditions,
                referenceDate: referenceDate
            )
        }
    }

    public static func nightScore(
        conditions: ViewingConditions,
        referenceDate: Date = Date(),
        timeZone: TimeZone? = nil
    ) -> Int {
        nightQuality(
            conditions: conditions,
            referenceDate: referenceDate,
            timeZone: timeZone
        )?.calculatedScore ?? 0
    }
}

/// Pure coordinate selection for Watch local weather acquisition.
public enum WatchLocalWeatherCoordinateSelection: Sendable {
    /// Site used for local weather when Connectivity fails.
    ///
    /// - Saved: always the pin (`selectedLocation` lat/lon) — never Watch GPS.
    /// - Current Location: watch GPS / request context.
    public static func coordinate(
        selectedLocation: SelectedLocation,
        currentLocationRequest: WatchCurrentLocationRequestContext?,
        watchGPS: (latitude: Double, longitude: Double)?
    ) -> (latitude: Double, longitude: Double)? {
        switch selectedLocation.source {
        case .saved:
            return (selectedLocation.latitude, selectedLocation.longitude)
        case .currentGPS:
            if let currentLocationRequest {
                return (currentLocationRequest.latitude, currentLocationRequest.longitude)
            }
            return watchGPS
        }
    }
}

/// Pure seam: when phone OQ accept succeeds, which brightness sample to upsert.
public enum WatchModeledBrightnessPhoneSync: Sendable {
    /// Sample to write into the durable watch brightness cache after a successful enhanced accept.
    public static func sampleToUpsert(
        transported: WatchObservingQualityPayload?,
        scorePresentationMode: WatchHeadlineScorePresentationMode?
    ) -> ModeledZenithBrightnessSample? {
        guard scorePresentationMode == .observingQuality,
              let transported,
              let sample = transported.makeSample() else {
            return nil
        }
        return sample
    }
}

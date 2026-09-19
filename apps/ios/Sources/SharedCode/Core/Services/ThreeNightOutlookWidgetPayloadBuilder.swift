import Foundation
import AstroEngine

public enum ThreeNightOutlookPublicationDecision {
    case publish(WidgetThreeNightOutlookSummary)
    case preserveExisting
    case unavailable(WidgetThreeNightOutlookSummary)
}

public enum ThreeNightOutlookWidgetPayloadBuilder {
    public static let labels = ["Tonight", "Tomorrow", "Day After"]

    public static func publicationDecision(
        conditions: ViewingConditions,
        existingSummary: WidgetThreeNightOutlookSummary?,
        referenceDate: Date,
        timeZone: TimeZone?,
        locationContext: CrossSurfaceLocationContext?,
        brightness: CrossSurfaceBrightnessInput = .loadFromAppGroup,
        baseURL: URL? = AppGroupStorage.containerURL
    ) -> ThreeNightOutlookPublicationDecision {
        // `locationContext == nil` means night-only OQ (no identity inference).
        switch ActiveObservingNightResolver.resolve(
            conditions: conditions, referenceDate: referenceDate, timeZone: timeZone
        ) {
        case let .resolved(first):
            guard let summary = makeSummary(
                conditions: conditions,
                firstResolution: first,
                referenceDate: referenceDate,
                locationContext: locationContext,
                brightness: brightness,
                baseURL: baseURL
            ) else {
                return .unavailable(makeUnavailableSummary(
                    generatedAt: conditions.fetchedAt, location: conditions.location,
                    timeZone: first.timeZone, referenceDate: referenceDate
                ))
            }
            return .publish(summary)
        case let .requiresActivePreviousPayload(resolvedTimeZone):
            if let existingSummary,
               isValidActivePreviousPayload(
                existingSummary, conditions: conditions, referenceDate: referenceDate,
                timeZone: resolvedTimeZone
               ) { return .preserveExisting }
            return .unavailable(makeUnavailableSummary(
                generatedAt: conditions.fetchedAt, location: conditions.location,
                timeZone: resolvedTimeZone, referenceDate: referenceDate
            ))
        case .unavailable:
            let resolvedTimeZone = timeZone
                ?? LocationTimeZoneResolver.approximate(longitude: conditions.location.longitude)
            return .unavailable(makeUnavailableSummary(
                generatedAt: conditions.fetchedAt, location: conditions.location,
                timeZone: resolvedTimeZone, referenceDate: referenceDate
            ))
        }
    }

    public static func makeSummary(
        conditions: ViewingConditions,
        firstResolution: TargetRecommendationContextResolution,
        referenceDate: Date,
        locationContext: CrossSurfaceLocationContext?,
        brightness: CrossSurfaceBrightnessInput = .loadFromAppGroup,
        baseURL: URL? = AppGroupStorage.containerURL
    ) -> WidgetThreeNightOutlookSummary? {
        // Day composition and per-night availability are the engine's
        // (`observing_night.compose_outlook`); this builder only assembles the
        // display payload over them. The composer re-runs the active-night
        // decision internally, which is exactly the one `firstResolution`
        // already carries.
        let outlook = NightOutlookComposer.compose(
            referenceDate: referenceDate,
            timeZone: firstResolution.timeZone,
            forecastStartTime: conditions.hourlyForecasts.first?.time,
            dailySunEvents: conditions.dailySunEvents.map(
                ObservingNightSelector.DailySunEvents.init
            ),
            dailyMoonCount: conditions.dailyMoonInfo.count,
            hourlyTimes: conditions.hourlyForecasts.map(\.time)
        )
        guard outlook.state == .resolved, outlook.nights.count == labels.count else {
            return nil
        }
        let resolutions = outlook.nights.compactMap { night in
            TargetRecommendationContextBuilder.resolve(
                conditions: conditions, dayOffset: night.dayOffset,
                referenceDate: referenceDate, timeZone: firstResolution.timeZone
            )
        }
        // The engine applies exactly the guards the builder applies to the same
        // arrays, so a composed slot cannot fail to build. The defensive branch
        // keeps the pre-migration "no context, no outlook" outcome.
        guard resolutions.count == labels.count else { return nil }

        // Authoritative context only — nil ⇒ night-only (exact night scores, no brightness).
        let sample: ModeledZenithBrightnessSample?
        if let locationContext, locationContext.isValidForBrightnessAssociation {
            sample = CrossSurfaceBrightnessSampleLoading.resolve(
                brightness, for: locationContext, baseURL: baseURL
            )
        } else {
            sample = nil
        }
        let effectiveContext: CrossSurfaceLocationContext? =
            (locationContext?.isValidForBrightnessAssociation == true) ? locationContext : nil

        var nights = resolutions.enumerated().map { index, resolution in
            makeNight(
                resolution,
                composed: outlook.nights[index],
                conditions: conditions,
                label: labels[index],
                isBest: false,
                locationContext: effectiveContext,
                sample: sample
            )
        }
        if let bestIndex = bestNightIndex(in: nights) {
            nights[bestIndex] = makeNight(
                resolutions[bestIndex],
                composed: outlook.nights[bestIndex],
                conditions: conditions,
                label: labels[bestIndex],
                isBest: true,
                locationContext: effectiveContext,
                sample: sample
            )
        }
        return WidgetThreeNightOutlookSummary(
            generatedAt: conditions.fetchedAt, locationName: conditions.location.name,
            latitude: conditions.location.latitude, longitude: conditions.location.longitude,
            savedLocationID: conditions.location.id,
            timeZoneIdentifier: firstResolution.timeZone.identifier, status: .available, nights: nights
        )
    }

    /// Delegates to ``AstroEngine/NightOutlookComposer/selectBestNight(_:)``
    /// (`observing_night.select_best`): only an available row with a score is
    /// eligible, the highest score wins, and a tie keeps the earliest row.
    public static func bestNightIndex(in nights: [WidgetThreeNightOutlookNight]) -> Int? {
        NightOutlookComposer.selectBestNight(nights.map {
            NightOutlookComposer.BestNightCandidate(
                status: $0.status.composedStatus, score: $0.score
            )
        })
    }

    /// Verifies that the raw hourly forecast stream continuously covers the
    /// full astronomical night. Hourly timestamps represent the start of their
    /// interval, so an interval may contain a non-hour-aligned boundary.
    ///
    /// The rule itself is the engine's
    /// (`observing_night.compose_outlook`, contracts/procedures/night-outlook.md);
    /// this entry point survives for callers that already hold a resolution.
    public static func hasCompleteHourlyCoverage(
        for resolution: TargetRecommendationContextResolution,
        conditions: ViewingConditions
    ) -> Bool {
        NightOutlookComposer.hasCompleteHourlyCoverage(
            astronomicalNightStart: resolution.context.astronomicalNightStart,
            astronomicalNightEnd: resolution.context.astronomicalNightEnd,
            hourlyTimes: conditions.hourlyForecasts.map(\.time)
        )
    }

    public static func makeUnavailableSummary(
        generatedAt: Date, location: CachedLocation, timeZone: TimeZone, referenceDate: Date
    ) -> WidgetThreeNightOutlookSummary {
        // The fallback observing dates are the engine's day rule; the zone this
        // branch resolved is the host's own precedence and stays here.
        let nights = NightOutlookComposer.fallbackNights(
            referenceDate: referenceDate, timeZone: timeZone
        ).map { night in
            WidgetThreeNightOutlookNight(
                id: "\(night.slotIndex)", displayLabel: labels[night.slotIndex],
                observingDate: night.observingDayStart,
                score: nil, verdict: "Unavailable", scoreTone: nil,
                astronomicalNightStart: nil, astronomicalNightEnd: nil, bestWindow: nil,
                statusText: "Forecast unavailable", status: .unavailable, isBestNight: false
            )
        }
        return WidgetThreeNightOutlookSummary(
            generatedAt: generatedAt, locationName: location.name,
            latitude: location.latitude, longitude: location.longitude,
            savedLocationID: location.id, timeZoneIdentifier: timeZone.identifier,
            status: .unavailable, nights: nights
        )
    }

    private static func makeNight(
        _ resolution: TargetRecommendationContextResolution,
        composed: NightOutlookNight,
        conditions: ViewingConditions,
        label: String,
        isBest: Bool,
        locationContext: CrossSurfaceLocationContext?,
        sample: ModeledZenithBrightnessSample?
    ) -> WidgetThreeNightOutlookNight {
        let assessment = resolution.context.nightQuality
        let start = composed.astronomicalNightStart ?? resolution.context.astronomicalNightStart
        let end = composed.astronomicalNightEnd ?? resolution.context.astronomicalNightEnd
        guard composed.status != .noAstronomicalNight else {
            return WidgetThreeNightOutlookNight(
                id: String(resolution.observingDate.timeIntervalSinceReferenceDate),
                displayLabel: label, observingDate: resolution.observingDate,
                score: nil, verdict: "No night", scoreTone: nil,
                astronomicalNightStart: start, astronomicalNightEnd: end, bestWindow: nil,
                statusText: "No astronomical night", status: .noAstronomicalNight, isBestNight: false
            )
        }
        guard composed.status == .available else {
            return WidgetThreeNightOutlookNight(
                id: String(resolution.observingDate.timeIntervalSinceReferenceDate),
                displayLabel: label, observingDate: resolution.observingDate,
                score: nil, verdict: "N/A", scoreTone: nil,
                astronomicalNightStart: start, astronomicalNightEnd: end,
                bestWindow: nil, statusText: "Needs fresh data",
                status: .unavailable, isBestNight: false
            )
        }
        let nightScore = assessment.calculatedScore
        let oqScore: Int
        if let locationContext {
            let snapshot = CrossSurfaceObservingQualityResolver.resolve(
                .init(
                    nightConditionsScore: nightScore,
                    location: locationContext,
                    sample: sample,
                    assessedAt: conditions.fetchedAt
                )
            )
            oqScore = snapshot.observingQualityScore
        } else {
            oqScore = nightScore
        }
        // Headline category/tone from OQ; best window and weather remain night-derived.
        let headlineVerdict = CrossSurfaceHeadlineScorePresentation.verdict(for: oqScore)
        let headlineTone = CrossSurfaceHeadlineScorePresentation.widgetTargetScoreTone(for: oqScore)
        return WidgetThreeNightOutlookNight(
            id: String(resolution.observingDate.timeIntervalSinceReferenceDate),
            displayLabel: label, observingDate: resolution.observingDate, score: oqScore,
            verdict: headlineVerdict, scoreTone: headlineTone,
            astronomicalNightStart: start,
            astronomicalNightEnd: end,
            bestWindow: assessment.bestWindow,
            statusText: assessment.bestWindow == nil ? "No best window available" : "Best window",
            status: .available, isBestNight: isBest,
            nightConditionsScore: nightScore,
            observingQualityScore: oqScore
        )
    }

    private static func isValidActivePreviousPayload(
        _ summary: WidgetThreeNightOutlookSummary, conditions: ViewingConditions,
        referenceDate: Date, timeZone: TimeZone
    ) -> Bool {
        let calendar = LocationTimeZoneResolver.calendar(for: timeZone)
        guard summary.status == .available, summary.hasCorrectlyOrderedNights(),
              let first = summary.nights.first,
              !calendar.isDate(first.observingDate, inSameDayAs: referenceDate),
              summary.locationMatches(conditions.location),
              summary.isWithinMaximumAge(WidgetThreeNightOutlookSummary.maximumAge, relativeTo: referenceDate),
              let start = first.astronomicalNightStart, let end = first.astronomicalNightEnd else { return false }
        return referenceDate >= start && referenceDate <= end
    }
}

import Foundation

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
        timeZone: TimeZone?
    ) -> ThreeNightOutlookPublicationDecision {
        switch ActiveObservingNightResolver.resolve(
            conditions: conditions, referenceDate: referenceDate, timeZone: timeZone
        ) {
        case let .resolved(first):
            guard let summary = makeSummary(
                conditions: conditions, firstResolution: first, referenceDate: referenceDate
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
        referenceDate: Date
    ) -> WidgetThreeNightOutlookSummary? {
        let calendar = LocationTimeZoneResolver.calendar(for: firstResolution.timeZone)
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let firstOffset = calendar.dateComponents(
            [.day], from: referenceDay, to: firstResolution.observingDate
        ).day ?? 0
        let resolutions = (0..<3).compactMap {
            TargetRecommendationContextBuilder.resolve(
                conditions: conditions, dayOffset: firstOffset + $0,
                referenceDate: referenceDate, timeZone: firstResolution.timeZone
            )
        }
        guard resolutions.count == labels.count else { return nil }

        var nights = resolutions.enumerated().map { index, resolution in
            makeNight(
                resolution,
                conditions: conditions,
                label: labels[index],
                isBest: false
            )
        }
        if let bestIndex = bestNightIndex(in: nights) {
            nights[bestIndex] = makeNight(
                resolutions[bestIndex],
                conditions: conditions,
                label: labels[bestIndex],
                isBest: true
            )
        }
        return WidgetThreeNightOutlookSummary(
            generatedAt: conditions.fetchedAt, locationName: conditions.location.name,
            latitude: conditions.location.latitude, longitude: conditions.location.longitude,
            savedLocationID: conditions.location.id,
            timeZoneIdentifier: firstResolution.timeZone.identifier, status: .available, nights: nights
        )
    }

    public static func bestNightIndex(in nights: [WidgetThreeNightOutlookNight]) -> Int? {
        let validIndices = nights.indices.filter {
            nights[$0].status == .available && nights[$0].score != nil
        }
        guard let first = validIndices.first else { return nil }
        return validIndices.dropFirst().reduce(first) { best, candidate in
            guard let bestScore = nights[best].score,
                  let candidateScore = nights[candidate].score else { return best }
            return candidateScore > bestScore ? candidate : best
        }
    }

    /// Verifies that the raw hourly forecast stream continuously covers the
    /// full astronomical night. Hourly timestamps represent the start of their
    /// interval, so an interval may contain a non-hour-aligned boundary.
    public static func hasCompleteHourlyCoverage(
        for resolution: TargetRecommendationContextResolution,
        conditions: ViewingConditions
    ) -> Bool {
        let start = resolution.context.astronomicalNightStart
        let end = resolution.context.astronomicalNightEnd
        guard start < end else { return false }

        let forecasts = conditions.hourlyForecasts.sorted { $0.time < $1.time }
        guard let cadence = nominalHourlyCadence(in: forecasts) else { return false }
        let relevant = forecasts.filter {
            $0.time <= end && $0.time.addingTimeInterval(cadence) >= start
        }
        guard let first = relevant.first, let last = relevant.last,
              first.time <= start,
              last.time.addingTimeInterval(cadence) >= end else { return false }

        return zip(relevant, relevant.dropFirst()).allSatisfy {
            abs($1.time.timeIntervalSince($0.time) - cadence) <= cadenceTolerance
        }
    }

    public static func makeUnavailableSummary(
        generatedAt: Date, location: CachedLocation, timeZone: TimeZone, referenceDate: Date
    ) -> WidgetThreeNightOutlookSummary {
        let calendar = LocationTimeZoneResolver.calendar(for: timeZone)
        let start = calendar.startOfDay(for: referenceDate)
        let nights = labels.enumerated().compactMap { index, label -> WidgetThreeNightOutlookNight? in
            guard let observingDate = calendar.date(byAdding: .day, value: index, to: start) else { return nil }
            return WidgetThreeNightOutlookNight(
                id: "\(index)", displayLabel: label, observingDate: observingDate,
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
        conditions: ViewingConditions,
        label: String,
        isBest: Bool
    ) -> WidgetThreeNightOutlookNight {
        let assessment = resolution.context.nightQuality
        let start = resolution.context.astronomicalNightStart
        let end = resolution.context.astronomicalNightEnd
        guard start < end else {
            return WidgetThreeNightOutlookNight(
                id: String(resolution.observingDate.timeIntervalSinceReferenceDate),
                displayLabel: label, observingDate: resolution.observingDate,
                score: nil, verdict: "No night", scoreTone: nil,
                astronomicalNightStart: start, astronomicalNightEnd: end, bestWindow: nil,
                statusText: "No astronomical night", status: .noAstronomicalNight, isBestNight: false
            )
        }
        guard hasCompleteHourlyCoverage(for: resolution, conditions: conditions) else {
            return WidgetThreeNightOutlookNight(
                id: String(resolution.observingDate.timeIntervalSinceReferenceDate),
                displayLabel: label, observingDate: resolution.observingDate,
                score: nil, verdict: "N/A", scoreTone: nil,
                astronomicalNightStart: start, astronomicalNightEnd: end,
                bestWindow: nil, statusText: "Needs fresh data",
                status: .unavailable, isBestNight: false
            )
        }
        let score = assessment.calculatedScore
        return WidgetThreeNightOutlookNight(
            id: String(resolution.observingDate.timeIntervalSinceReferenceDate),
            displayLabel: label, observingDate: resolution.observingDate, score: score,
            verdict: assessment.rating.shortLabel, scoreTone: tone(for: assessment.rating),
            astronomicalNightStart: resolution.context.astronomicalNightStart,
            astronomicalNightEnd: resolution.context.astronomicalNightEnd,
            bestWindow: assessment.bestWindow,
            statusText: assessment.bestWindow == nil ? "No best window available" : "Best window",
            status: .available, isBestNight: isBest
        )
    }

    private static let expectedHourlyCadence: TimeInterval = 60 * 60
    private static let cadenceTolerance: TimeInterval = 60

    private static func nominalHourlyCadence(in forecasts: [HourlyForecast]) -> TimeInterval? {
        let intervals = zip(forecasts, forecasts.dropFirst()).compactMap { first, second -> TimeInterval? in
            let interval = second.time.timeIntervalSince(first.time)
            return interval > 0 ? interval : nil
        }.sorted()
        guard !intervals.isEmpty else { return nil }
        let cadence = intervals[intervals.count / 2]
        guard abs(cadence - expectedHourlyCadence) <= cadenceTolerance else { return nil }
        return cadence
    }

    private static func tone(for rating: NightQualityAssessment.Rating) -> WidgetTargetScoreTone {
        switch rating {
        case .excellent: .positive
        case .good: .informational
        case .fair: .caution
        case .poor: .negative
        }
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

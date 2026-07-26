import Foundation
import SharedCode

enum ThreeNightOutlookPublicationDecision {
    case publish(WidgetThreeNightOutlookSummary)
    case preserveExisting
    case unavailable(WidgetThreeNightOutlookSummary)
}

enum ThreeNightOutlookWidgetPayloadBuilder {
    static let labels = ["Tonight", "Tomorrow", "Day After"]

    static func publicationDecision(
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
               ) {
                return .preserveExisting
            }
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

    static func makeSummary(
        conditions: ViewingConditions,
        firstResolution: TargetRecommendationContextResolution,
        referenceDate: Date
    ) -> WidgetThreeNightOutlookSummary? {
        let calendar = LocationTimeZoneResolver.calendar(for: firstResolution.timeZone)
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let firstOffset = calendar.dateComponents(
            [.day], from: referenceDay, to: firstResolution.observingDate
        ).day ?? 0
        let resolutions = (0..<3).map {
            TargetRecommendationContextBuilder.resolve(
                conditions: conditions, dayOffset: firstOffset + $0,
                referenceDate: referenceDate, timeZone: firstResolution.timeZone
            )
        }
        guard resolutions.allSatisfy({ $0 != nil }) else { return nil }

        var nights = resolutions.enumerated().map { index, resolution in
            makeNight(resolution!, label: labels[index], isBest: false)
        }
        if let bestIndex = bestNightIndex(in: nights) {
            nights[bestIndex] = makeNight(
                resolutions[bestIndex]!, label: labels[bestIndex], isBest: true
            )
        }
        return WidgetThreeNightOutlookSummary(
            generatedAt: conditions.fetchedAt, locationName: conditions.location.name,
            latitude: conditions.location.latitude, longitude: conditions.location.longitude,
            savedLocationID: conditions.location.id,
            timeZoneIdentifier: firstResolution.timeZone.identifier, status: .available, nights: nights
        )
    }

    static func bestNightIndex(in nights: [WidgetThreeNightOutlookNight]) -> Int? {
        let validIndices = nights.indices.filter {
            nights[$0].status == .available && nights[$0].score != nil
        }
        guard let first = validIndices.first else { return nil }
        return validIndices.dropFirst().reduce(first) { best, candidate in
            nights[candidate].score! > nights[best].score! ? candidate : best
        }
    }

    static func makeUnavailableSummary(
        generatedAt: Date, location: CachedLocation, timeZone: TimeZone, referenceDate: Date
    ) -> WidgetThreeNightOutlookSummary {
        let calendar = LocationTimeZoneResolver.calendar(for: timeZone)
        let start = calendar.startOfDay(for: referenceDate)
        let nights = labels.enumerated().map { index, label in
            WidgetThreeNightOutlookNight(
                id: "\(index)", displayLabel: label,
                observingDate: calendar.date(byAdding: .day, value: index, to: start)!,
                score: nil, verdict: "Unavailable", scoreTone: nil,
                astronomicalNightStart: nil, astronomicalNightEnd: nil, bestWindow: nil,
                statusText: "Outlook unavailable", status: .unavailable, isBestNight: false
            )
        }
        return WidgetThreeNightOutlookSummary(
            generatedAt: generatedAt, locationName: location.name,
            latitude: location.latitude, longitude: location.longitude,
            savedLocationID: location.id,
            timeZoneIdentifier: timeZone.identifier, status: .unavailable, nights: nights
        )
    }

    private static func makeNight(
        _ resolution: TargetRecommendationContextResolution, label: String, isBest: Bool
    ) -> WidgetThreeNightOutlookNight {
        let assessment = resolution.context.nightQuality
        guard !assessment.hourlyRatings.isEmpty else {
            return WidgetThreeNightOutlookNight(
                id: String(resolution.observingDate.timeIntervalSinceReferenceDate),
                displayLabel: label, observingDate: resolution.observingDate,
                score: nil, verdict: "No night", scoreTone: nil,
                astronomicalNightStart: resolution.context.astronomicalNightStart,
                astronomicalNightEnd: resolution.context.astronomicalNightEnd,
                bestWindow: nil,
                statusText: "No astronomical night", status: .noAstronomicalNight,
                isBestNight: false
            )
        }
        let score = assessment.calculatedScore
        return WidgetThreeNightOutlookNight(
            id: String(resolution.observingDate.timeIntervalSinceReferenceDate),
            displayLabel: label, observingDate: resolution.observingDate,
            score: score, verdict: assessment.rating.shortLabel,
            scoreTone: tone(for: assessment.rating),
            astronomicalNightStart: resolution.context.astronomicalNightStart,
            astronomicalNightEnd: resolution.context.astronomicalNightEnd,
            bestWindow: assessment.bestWindow,
            statusText: assessment.bestWindow == nil ? "No best window available" : "Best window",
            status: .available, isBestNight: isBest
        )
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
        _ summary: WidgetThreeNightOutlookSummary,
        conditions: ViewingConditions,
        referenceDate: Date,
        timeZone: TimeZone
    ) -> Bool {
        let calendar = LocationTimeZoneResolver.calendar(for: timeZone)
        guard summary.status == .available, summary.hasCorrectlyOrderedNights(),
              let first = summary.nights.first,
              !calendar.isDate(first.observingDate, inSameDayAs: referenceDate),
              summary.locationMatches(conditions.location),
              summary.isWithinMaximumAge(WidgetThreeNightOutlookSummary.maximumAge, relativeTo: referenceDate),
              let start = first.astronomicalNightStart,
              let end = first.astronomicalNightEnd else { return false }
        return referenceDate >= start && referenceDate <= end
    }
}

import Foundation
import SwiftUI
import XCTest
@testable import AstroViewingConditions
@testable import SharedCode

@MainActor
final class WidgetTonightTargetsTests: XCTestCase {
    private let timeZone = TimeZone(identifier: "America/Los_Angeles")!

    func testPayloadJSONRoundTripAndFoundationOnlyDependency() throws {
        let summary = makeSummary()
        let encoded = try JSONEncoder().encode(summary)
        let decoded = try JSONDecoder().decode(
            WidgetTonightTargetsSummary.self,
            from: encoded
        )

        XCTAssertEqual(decoded, summary)

        var legacyPayload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        legacyPayload.removeValue(forKey: "savedLocationID")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyPayload)
        XCTAssertNil(try JSONDecoder().decode(
            WidgetTonightTargetsSummary.self,
            from: legacyData
        ).savedLocationID)

        let source = try sourceText(
            "Sources/SharedCode/Core/Models/WidgetTonightTargetsSummary.swift"
        )
        XCTAssertTrue(source.contains("import Foundation"))
        XCTAssertFalse(source.contains("import SwiftUI"))
        XCTAssertFalse(source.contains("import WidgetKit"))
    }

    func testMaximumAgeMatchesConditionsCacheAndRejectsOlderSummary() {
        let generatedAt = date(day: 25, hour: 20)
        let summary = makeSummary(generatedAt: generatedAt)
        let maximumAge = WidgetTonightTargetsSummary.maximumAge

        XCTAssertEqual(maximumAge, SharedConditionsRepository.maximumAge)
        XCTAssertTrue(summary.isWithinMaximumAge(
            maximumAge,
            relativeTo: generatedAt.addingTimeInterval(maximumAge - 1)
        ))
        XCTAssertFalse(summary.isWithinMaximumAge(
            maximumAge,
            relativeTo: generatedAt.addingTimeInterval(maximumAge)
        ))
        XCTAssertFalse(summary.isWithinMaximumAge(
            maximumAge,
            relativeTo: generatedAt.addingTimeInterval(maximumAge + 1)
        ))
        XCTAssertFalse(summary.isWithinMaximumAge(
            maximumAge,
            relativeTo: generatedAt.addingTimeInterval(-1)
        ))
    }

    func testLocationAndObservingNightValidationAcrossMidnight() {
        let summary = makeSummary(
            observingDate: date(day: 25),
            nightStart: date(day: 25, hour: 22),
            nightEnd: date(day: 26, hour: 4)
        )

        XCTAssertTrue(summary.locationMatches(latitude: 45.5, longitude: -122.7))
        XCTAssertFalse(summary.locationMatches(latitude: 47.6, longitude: -122.7))
        XCTAssertTrue(summary.matchesCurrentObservingNight(
            relativeTo: date(day: 25, hour: 14)
        ))
        XCTAssertTrue(summary.matchesCurrentObservingNight(
            relativeTo: date(day: 26, hour: 1)
        ))
        XCTAssertFalse(summary.matchesCurrentObservingNight(
            relativeTo: date(day: 26, hour: 5)
        ))
        XCTAssertFalse(summary.matchesCurrentObservingNight(
            relativeTo: date(day: 27, hour: 1)
        ))
    }

    func testSavedLocationIdentityRejectsNearbyDifferentSiteAndAcceptsSameSite() {
        let firstID = UUID()
        let secondID = UUID()
        let summary = makeSummary(savedLocationID: firstID)
        let nearbySecondSite = SelectedLocation(
            source: .saved,
            id: secondID,
            name: "Nearby",
            latitude: 45.500001,
            longitude: -122.699999
        )
        let sameSiteWithUpdatedCoordinates = SelectedLocation(
            source: .saved,
            id: firstID,
            name: "Home",
            latitude: 46.0,
            longitude: -123.0
        )

        XCTAssertFalse(summary.locationMatches(nearbySecondSite))
        XCTAssertTrue(summary.locationMatches(sameSiteWithUpdatedCoordinates))
        XCTAssertFalse(summary.locationMatches(SelectedLocation(
            source: .currentGPS,
            name: "Current Location",
            latitude: 45.5,
            longitude: -122.7
        )))
        XCTAssertFalse(summary.locationMatches(CachedLocation(
            name: "Current Location", latitude: 45.5, longitude: -122.7
        )))
    }

    func testLegacyAndCurrentLocationUseStrictCoordinateFallback() {
        let legacy = makeSummary()
        XCTAssertTrue(legacy.locationMatches(SelectedLocation(
            source: .currentGPS,
            name: "Current Location",
            latitude: 45.5,
            longitude: -122.7
        )))
        XCTAssertFalse(legacy.locationMatches(SelectedLocation(
            source: .currentGPS,
            name: "Nearby",
            latitude: 45.50002,
            longitude: -122.7
        )))
        XCTAssertFalse(legacy.locationMatches(SelectedLocation(
            source: .saved,
            id: UUID(),
            name: "Home",
            latitude: 45.5,
            longitude: -122.7
        )))
        XCTAssertFalse(legacy.locationMatches(CachedLocation(
            id: UUID(), name: "Home", latitude: 45.5, longitude: -122.7
        )))
    }

    func testContextBuilderPreservesTodayTomorrowAndDayAfterInputs() {
        let referenceDate = date(day: 25, hour: 12)
        let conditions = makeConditions(referenceDate: referenceDate)

        for dayOffset in 0...2 {
            let resolution = TargetRecommendationContextBuilder.resolve(
                conditions: conditions,
                dayOffset: dayOffset,
                referenceDate: referenceDate,
                timeZone: timeZone
            )
            let expectedObservingDate = calendar.date(
                byAdding: .day,
                value: dayOffset,
                to: calendar.startOfDay(for: referenceDate)
            )!
            let expectedStart = date(day: 25 + dayOffset, hour: 22)
            let expectedEnd = date(day: 26 + dayOffset, hour: 4)

            XCTAssertEqual(resolution?.observingDate, expectedObservingDate)
            XCTAssertEqual(resolution?.context.location.latitude, conditions.location.latitude)
            XCTAssertEqual(resolution?.context.astronomicalNightStart, expectedStart)
            XCTAssertEqual(resolution?.context.astronomicalNightEnd, expectedEnd)
            XCTAssertEqual(
                resolution?.context.moonInfo.illumination,
                conditions.dailyMoonInfo[dayOffset].illumination
            )
            XCTAssertEqual(resolution?.context.nightQuality.nightStart, expectedStart)
            XCTAssertEqual(
                resolution?.context.nightQuality.nightEnd,
                expectedEnd.addingTimeInterval(-3600)
            )
        }
    }

    func testDashboardComputedPresentationUsesBuilderForEverySelectedDay() {
        let referenceDate = date(day: 25, hour: 12)
        let conditions = makeConditions(referenceDate: referenceDate)
        let recorder = RecordingRecommendationService()
        let viewModel = DashboardViewModel(
            targetRecommendationService: recorder,
            now: { referenceDate }
        )
        viewModel.viewingConditions = conditions

        for selectedDay in DashboardViewModel.DaySelection.allCases {
            viewModel.selectedDay = selectedDay
            _ = viewModel.currentBestTargetsPresentation

            let expected = TargetRecommendationContextBuilder.resolve(
                conditions: conditions,
                dayOffset: selectedDay.rawValue,
                referenceDate: referenceDate,
                timeZone: timeZone
            )
            XCTAssertEqual(
                recorder.contexts.last?.astronomicalNightStart,
                expected?.context.astronomicalNightStart
            )
            XCTAssertEqual(
                recorder.contexts.last?.astronomicalNightEnd,
                expected?.context.astronomicalNightEnd
            )
            XCTAssertEqual(
                recorder.contexts.last?.moonInfo.illumination,
                expected?.context.moonInfo.illumination
            )
        }
        XCTAssertEqual(recorder.requestedLimits, [100, 100, 100])
    }

    func testContextBuilderPreservesDashboardFallbackWhenHourlyForecastsAreEmpty() {
        let referenceDate = date(day: 25, hour: 12)
        let conditions = makeConditions(
            referenceDate: referenceDate,
            includesForecasts: false
        )
        let resolution = TargetRecommendationContextBuilder.resolve(
            conditions: conditions,
            dayOffset: 1,
            referenceDate: referenceDate,
            timeZone: timeZone
        )

        XCTAssertNotNil(resolution)
        XCTAssertEqual(
            resolution?.context.astronomicalNightStart,
            date(day: 26, hour: 22)
        )
        XCTAssertTrue(resolution?.context.nightQuality.hourlyRatings.isEmpty == true)
    }

    func testWidgetContextResolverSelectsCurrentOrActivePreviousObservingNight() {
        let conditions = makeConditions(referenceDate: date(day: 25, hour: 12))
        let cases: [(referenceDate: Date, expectedObservingDay: Int)] = [
            (date(day: 25, hour: 14), 25),
            (date(day: 25, hour: 23), 25),
            (date(day: 26, hour: 1), 25),
            (date(day: 26, hour: 4), 25),
            (date(day: 26, hour: 4).addingTimeInterval(1), 26)
        ]

        for testCase in cases {
            let decision = TonightTargetsWidgetContextResolver.publicationDecision(
                conditions: conditions,
                existingSummary: nil,
                referenceDate: testCase.referenceDate,
                timeZone: timeZone
            )
            guard case let .publish(resolution) = decision else {
                return XCTFail(
                    "Expected a publish decision for \(testCase.referenceDate)"
                )
            }

            XCTAssertTrue(
                calendar.isDate(
                    resolution.observingDate,
                    inSameDayAs: date(day: testCase.expectedObservingDay)
                ),
                "Unexpected observing date for \(testCase.referenceDate)"
            )
        }
    }

    func testAfterMidnightPublicationKeepsPreviousNightContextAndPayloadAligned() {
        let conditions = makeConditions(referenceDate: date(day: 25, hour: 12))
        let referenceDate = date(day: 26, hour: 1)
        let decision = TonightTargetsWidgetContextResolver.publicationDecision(
            conditions: conditions,
            existingSummary: nil,
            referenceDate: referenceDate,
            timeZone: timeZone
        )
        guard case let .publish(resolution) = decision else {
            return XCTFail("Expected active-night publication")
        }

        XCTAssertEqual(resolution.observingDate, date(day: 25))
        XCTAssertEqual(resolution.context.astronomicalNightStart, date(day: 25, hour: 22))
        XCTAssertEqual(resolution.context.astronomicalNightEnd, date(day: 26, hour: 4))
        XCTAssertEqual(
            resolution.context.moonInfo.illumination,
            conditions.dailyMoonInfo[0].illumination
        )

        let refreshedPayload = TonightTargetsWidgetPayloadBuilder.makeSummary(
            conditions: conditions,
            resolution: resolution,
            recommendations: [makeRecommendation(id: "active-night", score: 91)]
        )
        XCTAssertEqual(refreshedPayload.observingDate, date(day: 25))
        XCTAssertEqual(refreshedPayload.astronomicalNightStart, date(day: 25, hour: 22))
        XCTAssertEqual(refreshedPayload.astronomicalNightEnd, date(day: 26, hour: 4))
    }

    func testFreshPostMidnightConditionsBeginOnCurrentCalendarDay() {
        let referenceDate = date(day: 26, hour: 1)
        let conditions = makeConditions(
            referenceDate: referenceDate,
            dataStartDay: 26
        )

        XCTAssertEqual(conditions.hourlyForecasts.first?.time, date(day: 26))
        XCTAssertEqual(
            conditions.dailySunEvents.first?.astronomicalTwilightBegin,
            date(day: 26, hour: 4)
        )
        XCTAssertEqual(
            conditions.dailySunEvents.first?.astronomicalTwilightEnd,
            date(day: 26, hour: 22)
        )
        XCTAssertEqual(conditions.dailyMoonInfo.first?.illumination, 20)
        XCTAssertNil(TargetRecommendationContextBuilder.resolve(
            conditions: conditions,
            dayOffset: -1,
            referenceDate: referenceDate,
            timeZone: timeZone
        ))
    }

    func testFreshPostMidnightConditionsPreserveValidActiveNightPayload() {
        let referenceDate = date(day: 26, hour: 1)
        let conditions = makeConditions(
            referenceDate: referenceDate,
            dataStartDay: 26
        )
        let activePayload = makeSummary(
            generatedAt: referenceDate,
            observingDate: date(day: 25),
            nightStart: date(day: 25, hour: 22),
            nightEnd: date(day: 26, hour: 4)
        )

        let decision = TonightTargetsWidgetContextResolver.publicationDecision(
            conditions: conditions,
            existingSummary: activePayload,
            referenceDate: referenceDate,
            timeZone: timeZone
        )

        guard case .preserveExisting = decision else {
            return XCTFail("Expected the active July 25 payload to be preserved")
        }
    }

    func testFreshPostMidnightConditionsWithoutValidActivePayloadAreUnavailable() {
        let referenceDate = date(day: 26, hour: 1)
        let conditions = makeConditions(
            referenceDate: referenceDate,
            dataStartDay: 26
        )

        let decision = TonightTargetsWidgetContextResolver.publicationDecision(
            conditions: conditions,
            existingSummary: nil,
            referenceDate: referenceDate,
            timeZone: timeZone
        )

        guard case .unavailable = decision else {
            return XCTFail("Expected unavailable instead of July 26 evening targets")
        }
    }

    func testFreshPostMidnightConditionsRejectEveryInvalidPhaseTwoPayload() {
        let referenceDate = date(day: 26, hour: 1)
        let conditions = makeConditions(referenceDate: referenceDate, dataStartDay: 26)
        let invalidPayloads: [WidgetTonightTargetsSummary?] = [
            nil,
            makeSummary(
                generatedAt: date(day: 25, hour: 21).addingTimeInterval(-1),
                observingDate: date(day: 25),
                nightStart: date(day: 25, hour: 22),
                nightEnd: date(day: 26, hour: 4)
            ),
            makeSummary(
                generatedAt: date(day: 25, hour: 23), latitude: 47.6,
                observingDate: date(day: 25),
                nightStart: date(day: 25, hour: 22),
                nightEnd: date(day: 26, hour: 4)
            ),
            makeSummary(
                generatedAt: date(day: 25, hour: 23),
                observingDate: date(day: 24),
                nightStart: date(day: 24, hour: 22),
                nightEnd: date(day: 25, hour: 4)
            ),
            makeSummary(
                generatedAt: date(day: 25, hour: 23),
                observingDate: date(day: 25),
                nightStart: date(day: 25, hour: 22),
                nightEnd: date(day: 26, hour: 4),
                status: .available, targets: []
            ),
            makeSummary(
                generatedAt: date(day: 25, hour: 23),
                observingDate: date(day: 25),
                nightStart: date(day: 25, hour: 22),
                nightEnd: date(day: 26, hour: 4),
                status: .unavailable, targets: []
            )
        ]

        for payload in invalidPayloads {
            let decision = TonightTargetsWidgetContextResolver.publicationDecision(
                conditions: conditions, existingSummary: payload,
                referenceDate: referenceDate, timeZone: timeZone
            )
            guard case .unavailable = decision else {
                return XCTFail("Expected invalid Phase 2 payload to be rejected")
            }
        }
    }

    func testFreshPostMidnightConditionsPublishUpcomingEveningAfterNightEnd() throws {
        let referenceDate = date(day: 26, hour: 4).addingTimeInterval(1)
        let conditions = makeConditions(
            referenceDate: referenceDate,
            dataStartDay: 26
        )

        let decision = TonightTargetsWidgetContextResolver.publicationDecision(
            conditions: conditions,
            existingSummary: nil,
            referenceDate: referenceDate,
            timeZone: timeZone
        )

        guard case let .publish(resolution) = decision else {
            return XCTFail("Expected July 26 upcoming-evening publication")
        }
        XCTAssertEqual(resolution.observingDate, date(day: 26))
        XCTAssertEqual(
            resolution.context.moonInfo.illumination,
            conditions.dailyMoonInfo[0].illumination
        )
    }

    func testBuilderPreservesCanonicalOrderAndKeepsOnlyFirstThreeWithoutFiltering() {
        let savedLocationID = UUID()
        let conditions = makeConditions(
            referenceDate: date(day: 25, hour: 12), locationID: savedLocationID
        )
        let resolution = TargetRecommendationContextBuilder.resolve(
            conditions: conditions,
            dayOffset: 0,
            referenceDate: date(day: 25, hour: 12),
            timeZone: timeZone
        )!
        let recommendations = [
            makeRecommendation(id: "first", score: 10),
            makeRecommendation(id: "second", score: 95),
            makeRecommendation(id: "third", score: 45),
            makeRecommendation(id: "fourth", score: 80)
        ]

        let summary = TonightTargetsWidgetPayloadBuilder.makeSummary(
            conditions: conditions,
            resolution: resolution,
            recommendations: recommendations
        )

        XCTAssertEqual(summary.targets.map(\.targetID), ["first", "second", "third"])
        XCTAssertEqual(summary.targets.map(\.score), [10, 95, 45])
        XCTAssertEqual(summary.generatedAt, conditions.fetchedAt)
        XCTAssertEqual(summary.savedLocationID, savedLocationID)
        XCTAssertEqual(summary.status, .available)
    }

    func testBuilderMapsZeroThroughThreeTargetsAndResolvesEmptyStatus() {
        let conditions = makeConditions(referenceDate: date(day: 25, hour: 12))
        let resolution = TargetRecommendationContextBuilder.resolve(
            conditions: conditions,
            dayOffset: 0,
            referenceDate: date(day: 25, hour: 12),
            timeZone: timeZone
        )!
        let recommendations = (0..<3).map {
            makeRecommendation(id: "target-\($0)", score: 90 - $0)
        }

        for count in 0...3 {
            let summary = TonightTargetsWidgetPayloadBuilder.makeSummary(
                conditions: conditions,
                resolution: resolution,
                recommendations: Array(recommendations.prefix(count))
            )

            XCTAssertEqual(summary.targets.count, count)
            XCTAssertEqual(
                summary.status,
                count == 0 ? .noTargets : .available
            )
        }
    }

    func testUnavailablePayloadUsesProvidedSourceFreshnessAndHasNoTargets() {
        let sourceDate = date(day: 25, hour: 12)
        let location = CachedLocation(
            name: "Home",
            latitude: 45.5,
            longitude: -122.7
        )

        let summary = TonightTargetsWidgetPayloadBuilder.makeUnavailableSummary(
            generatedAt: sourceDate,
            location: location,
            timeZone: timeZone,
            referenceDate: sourceDate
        )

        XCTAssertEqual(summary.generatedAt, sourceDate)
        XCTAssertEqual(summary.status, .unavailable)
        XCTAssertTrue(summary.targets.isEmpty)
    }

    func testScoreToneIsResolvedByExistingAppSemantics() {
        let conditions = makeConditions(referenceDate: date(day: 25, hour: 12))
        let resolution = TargetRecommendationContextBuilder.resolve(
            conditions: conditions,
            dayOffset: 0,
            referenceDate: date(day: 25, hour: 12),
            timeZone: timeZone
        )!
        let recommendations = [80, 60, 40, 39].map {
            makeRecommendation(id: "score-\($0)", score: $0)
        }

        let summary = TonightTargetsWidgetPayloadBuilder.makeSummary(
            conditions: conditions,
            resolution: resolution,
            recommendations: recommendations
        )

        XCTAssertEqual(
            summary.targets.map(\.scoreTone),
            [.positive, .caution, .negative]
        )
        XCTAssertEqual(TargetScoreColorProvider.category(for: 39), .poor)
    }

    func testTonightTargetsPersistencePolicyRetainsOnlyUsableActivePayloads() {
        let referenceDate = date(day: 25, hour: 23)
        let location = CachedLocation(name: "Home", latitude: 45.5, longitude: -122.7)
        let available = makeSummary(generatedAt: referenceDate)
        let noTargets = makeSummary(
            generatedAt: referenceDate,
            status: .noTargets,
            targets: []
        )
        let unavailable = makeSummary(
            generatedAt: referenceDate,
            status: .unavailable,
            targets: []
        )

        XCTAssertTrue(TonightTargetsPersistencePolicy.shouldSave(
            candidate: available, existing: nil, targetLocation: location, referenceDate: referenceDate
        ))
        XCTAssertTrue(TonightTargetsPersistencePolicy.shouldSave(
            candidate: noTargets, existing: nil, targetLocation: location, referenceDate: referenceDate
        ))
        XCTAssertFalse(TonightTargetsPersistencePolicy.shouldSave(
            candidate: unavailable, existing: available, targetLocation: location, referenceDate: referenceDate
        ))
        XCTAssertTrue(TonightTargetsPersistencePolicy.shouldSave(
            candidate: unavailable,
            existing: makeSummary(generatedAt: referenceDate.addingTimeInterval(
                -WidgetTonightTargetsSummary.maximumAge
            )),
            targetLocation: location,
            referenceDate: referenceDate
        ))
        XCTAssertTrue(TonightTargetsPersistencePolicy.shouldSave(
            candidate: unavailable,
            existing: makeSummary(generatedAt: referenceDate, latitude: 47.6),
            targetLocation: location,
            referenceDate: referenceDate
        ))
        XCTAssertTrue(TonightTargetsPersistencePolicy.shouldSave(
            candidate: available, existing: unavailable, targetLocation: location, referenceDate: referenceDate
        ))
    }

    func testTonightTargetsPersistencePolicyPreservesActivePreviousNightAfterMidnight() {
        let referenceDate = date(day: 26, hour: 1)
        let location = CachedLocation(name: "Home", latitude: 45.5, longitude: -122.7)
        let activePreviousNight = makeSummary(
            generatedAt: referenceDate,
            observingDate: date(day: 25),
            nightStart: date(day: 25, hour: 22),
            nightEnd: date(day: 26, hour: 4)
        )
        let unavailable = makeSummary(
            generatedAt: referenceDate,
            observingDate: date(day: 26),
            nightStart: nil,
            nightEnd: nil,
            status: .unavailable,
            targets: []
        )

        XCTAssertFalse(TonightTargetsPersistencePolicy.shouldSave(
            candidate: unavailable,
            existing: activePreviousNight,
            targetLocation: location,
            referenceDate: referenceDate
        ))
    }

    func testTargetsFallbackAgeLocationAndNightBoundaries() {
        let referenceDate = date(day: 25, hour: 23)
        let location = CachedLocation(name: "Home", latitude: 45.5, longitude: -122.7)
        let maximumAge = WidgetTonightTargetsSummary.maximumAge
        let cases: [(String, WidgetTonightTargetsSummary, Bool)] = [
            ("just inside", makeSummary(generatedAt: referenceDate.addingTimeInterval(-maximumAge + 1)), true),
            ("exactly maximum age", makeSummary(generatedAt: referenceDate.addingTimeInterval(-maximumAge)), false),
            ("same night but old", makeSummary(generatedAt: referenceDate.addingTimeInterval(-maximumAge - 1)), false),
            (
                "fresh wrong observing night",
                makeSummary(
                    generatedAt: referenceDate,
                    observingDate: date(day: 24),
                    nightStart: date(day: 24, hour: 22),
                    nightEnd: date(day: 25, hour: 4)
                ),
                false
            ),
            ("fresh wrong location", makeSummary(generatedAt: referenceDate, latitude: 47.6), false)
        ]

        for (name, summary, expected) in cases {
            XCTAssertEqual(
                TonightTargetsPersistencePolicy.isValidLastKnownGood(
                    summary,
                    for: location,
                    referenceDate: referenceDate
                ),
                expected,
                name
            )
        }
    }

    func testUnavailableEntrySelectionRetainsValidCachedTargetsAsFallback() {
        let referenceDate = date(day: 25, hour: 23)
        let cached = makeSummary(generatedAt: referenceDate)
        let selection = selectUnavailableEntry(
            existing: cached,
            referenceDate: referenceDate
        )

        XCTAssertFalse(selection.shouldSaveCandidate)
        guard case let .available(displayed) = selection.entry.state else {
            return XCTFail("Expected cached targets to be displayed")
        }
        XCTAssertEqual(displayed, cached)
        XCTAssertEqual(selection.displayedSummary, cached)
        XCTAssertEqual(selection.entry.dataStatus?.provenance, .fallback)
    }

    func testUnavailableEntrySelectionUsesCandidateForExpiredCache() {
        let referenceDate = date(day: 25, hour: 23)
        let cached = makeSummary(generatedAt: referenceDate.addingTimeInterval(
            -WidgetTonightTargetsSummary.maximumAge
        ))
        let selection = selectUnavailableEntry(
            existing: cached,
            referenceDate: referenceDate
        )

        assertUnavailableCandidateSelected(selection)
    }

    func testUnavailableEntrySelectionUsesCandidateForLocationMismatch() {
        let referenceDate = date(day: 25, hour: 23)
        let selection = selectUnavailableEntry(
            existing: makeSummary(generatedAt: referenceDate, latitude: 47.6),
            referenceDate: referenceDate
        )

        assertUnavailableCandidateSelected(selection)
    }

    func testUnavailableEntrySelectionUsesCandidateForUnavailableCache() {
        let referenceDate = date(day: 25, hour: 23)
        let selection = selectUnavailableEntry(
            existing: makeSummary(
                generatedAt: referenceDate,
                status: .unavailable,
                targets: []
            ),
            referenceDate: referenceDate
        )

        assertUnavailableCandidateSelected(selection)
    }

    func testUnavailableEntrySelectionRetainsValidNoTargetsAsFallback() {
        let referenceDate = date(day: 25, hour: 23)
        let cached = makeSummary(
            generatedAt: referenceDate,
            status: .noTargets,
            targets: []
        )
        let selection = selectUnavailableEntry(
            existing: cached,
            referenceDate: referenceDate
        )

        XCTAssertFalse(selection.shouldSaveCandidate)
        guard case .noTargets = selection.entry.state else {
            return XCTFail("Expected cached no-targets state to be displayed")
        }
        XCTAssertEqual(selection.displayedSummary, cached)
        XCTAssertEqual(selection.entry.dataStatus?.provenance, .fallback)
        XCTAssertEqual(selection.entry.dataStatus?.dataAsOf, cached.generatedAt)
    }

    func testPositionCompositionIsAppSideAndHandlesAllOptionalCombinations() {
        XCTAssertEqual(
            TonightTargetsWidgetPayloadBuilder.positionLabel(
                direction: "SW",
                altitude: 47.6
            ),
            "SW · 48°"
        )
        XCTAssertEqual(
            TonightTargetsWidgetPayloadBuilder.positionLabel(
                direction: "SW",
                altitude: nil
            ),
            "SW"
        )
        XCTAssertEqual(
            TonightTargetsWidgetPayloadBuilder.positionLabel(
                direction: nil,
                altitude: 47.6
            ),
            "48°"
        )
        XCTAssertNil(TonightTargetsWidgetPayloadBuilder.positionLabel(
            direction: nil,
            altitude: nil
        ))
    }

    func testNoTargetsAndUnavailablePayloadsReplacePreviousValidCache() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let available = makeSummary(status: .available, targets: [makeTarget()])
        XCTAssertTrue(AppGroupStorage.writeWidgetTonightTargetsSummary(
            available,
            baseURL: tempDirectory
        ))
        XCTAssertEqual(
            AppGroupStorage.readWidgetTonightTargetsSummary(baseURL: tempDirectory)?.status,
            .available
        )

        let noTargets = makeSummary(status: .noTargets, targets: [])
        XCTAssertTrue(AppGroupStorage.writeWidgetTonightTargetsSummary(
            noTargets,
            baseURL: tempDirectory
        ))
        XCTAssertEqual(
            AppGroupStorage.readWidgetTonightTargetsSummary(baseURL: tempDirectory),
            noTargets
        )

        let unavailable = makeSummary(status: .unavailable, targets: [])
        XCTAssertTrue(AppGroupStorage.writeWidgetTonightTargetsSummary(
            unavailable,
            baseURL: tempDirectory
        ))
        XCTAssertEqual(
            AppGroupStorage.readWidgetTonightTargetsSummary(baseURL: tempDirectory),
            unavailable
        )
    }

    func testMissingLegacyTargetsCacheReturnsNil() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        XCTAssertNil(AppGroupStorage.readWidgetTonightTargetsSummary(
            baseURL: tempDirectory
        ))
    }

    func testPayloadPreservesCompleteLongTargetName() {
        let longName = "NGC 869/884 Double Cluster"
        XCTAssertEqual(makeTarget(name: longName).displayName, longName)
    }

    func testMissingBestTimeIsOmittedAsACompleteValue() {
        XCTAssertNil(WidgetTonightTargetsPresentation.bestTimeText(
            nil,
            timeZone: timeZone
        ))
    }

    func testWidgetBoundaryHasNoRecommendationCallsThresholdsOrDeepLinks() throws {
        let widgetFiles = [
            "Sources/Widgets/TonightTargetsWidget.swift",
            "Sources/Widgets/TonightTargetsEntry.swift",
            "Sources/Widgets/TonightTargetsTimelineProvider.swift",
            "Sources/Widgets/TonightTargetsWidgetMediumEntryView.swift",
            "Sources/Widgets/WidgetTonightTargetsPresentation.swift"
        ]
        let source = try widgetFiles.map(sourceText).joined(separator: "\n")

        XCTAssertFalse(source.contains("TargetRecommendationService"))
        XCTAssertFalse(source.contains("TargetRecommendationProviding"))
        XCTAssertFalse(source.contains(".recommendations("))
        XCTAssertFalse(source.contains("TargetScoreColorProvider"))
        XCTAssertFalse(source.contains("case 80"))
        XCTAssertFalse(source.contains("case 60"))
        XCTAssertFalse(source.contains("positionLabel(direction"))
        XCTAssertFalse(source.contains("widgetURL"))
        XCTAssertFalse(source.contains("Link("))
        XCTAssertFalse(source.contains("onOpenURL"))
        XCTAssertFalse(source.contains("URL("))
    }

    func testTargetsProviderRefreshesThroughSharedPipelineAndSafelyFallsBack() throws {
        let source = try sourceText("Sources/Widgets/TonightTargetsTimelineProvider.swift")
        XCTAssertTrue(source.contains("SharedConditionsRepository().conditions"))
        XCTAssertTrue(source.contains("TonightTargetsWidgetRefreshPipeline.makeSummary"))
        XCTAssertTrue(source.contains("saveWidgetTonightTargetsSummaryAsync"))
        XCTAssertTrue(source.contains("context.isPreview"))
        XCTAssertTrue(source.contains("Timeline invocation"))
        XCTAssertTrue(source.contains("Using matching last-known-good Targets summary"))
        XCTAssertFalse(source.contains("private func isCurrent("))
        XCTAssertFalse(source.contains("payloadMaximumAge"))

    }

    func testLongNameViewUsesIntrinsicWrappingInsteadOfTruncation() throws {
        let source = try sourceText(
            "Sources/Widgets/TonightTargetsWidgetMediumEntryView.swift"
        )
        XCTAssertTrue(source.contains(".fixedSize(horizontal: false, vertical: true)"))
        XCTAssertFalse(source.contains(".truncationMode"))
        XCTAssertFalse(source.contains(".lineLimit"))
        XCTAssertFalse(source.contains(".dynamicTypeSize("))
        XCTAssertFalse(source.contains(".minimumScaleFactor"))
        XCTAssertFalse(source.contains(".system(size:"))
        XCTAssertTrue(source.contains("Text(\"Tonight\")"))
        XCTAssertTrue(source.contains("Text(\"Tonight’s Targets\")"))
        XCTAssertTrue(source.contains(".font(.caption2.weight(.semibold))"))
    }

    func testReducedCompactAndMinimalCandidateHierarchyRetainsIdentity() throws {
        let source = try sourceText(
            "Sources/Widgets/TonightTargetsWidgetMediumEntryView.swift"
        )

        XCTAssertEqual(
            source.components(separatedBy: "showsHeader: false").count - 1,
            1,
            "Only the shared reduced-identity candidate may remove the full header"
        )
        XCTAssertTrue(source.contains("private func reducedIdentityCandidate("))
        XCTAssertTrue(source.contains("Image(systemName: WidgetAppIdentity.symbol)"))
        let reducedIdentitySection = try sourceSection(
            in: source,
            from: "private func reducedIdentityCandidate(",
            through: "private func content("
        )
        XCTAssertFalse(reducedIdentitySection.contains(
            "Image(systemName: \"scope\")"
        ))
        XCTAssertTrue(reducedIdentitySection.contains(
            "Text(\"Tonight’s Targets\")"
        ))
        XCTAssertTrue(source.contains("Text(\"Tonight\")"))
        XCTAssertTrue(source.contains(".font(.caption2.weight(.semibold))"))
        XCTAssertTrue(source.contains(".foregroundStyle(.secondary)"))
        XCTAssertTrue(source.contains(
            ".fixedSize(horizontal: true, vertical: false)"
        ))

        let fullHeaderCandidates = contentCandidateArguments(in: source)
            .filter { $0.contains("showsHeader: true") }
        XCTAssertEqual(fullHeaderCandidates.count, 4)
        XCTAssertTrue(fullHeaderCandidates.allSatisfy {
            $0.contains("showsSymbol: true")
        })
        XCTAssertFalse(fullHeaderCandidates.contains {
            $0.contains("showsSymbol: false")
        })

        let compactBranch = try sourceSection(
            in: source,
            from: "case .compact:",
            through: "case .minimal:"
        )
        let normalizedCompactBranch = normalizedSource(compactBranch)
        let fullHeaderCandidate = try XCTUnwrap(normalizedCompactBranch.range(
            of: "content( targetCount: 2, showsHeader: true, showsLocation: false, "
                + "includesCategory: false, includesPosition: true, showsSymbol: true, "
                + "showsScore: true, showsBestTime: true, rowStyle: .regular )"
        ))
        let completeReducedCandidate = try XCTUnwrap(normalizedCompactBranch.range(
            of: "reducedIdentityCandidate( targetCount: 2, showsScore: true, "
                + "showsBestTime: true, rowStyle: .reducedCompact )"
        ))
        let firstOneTargetFallback = try XCTUnwrap(normalizedCompactBranch.range(
            of: "reducedIdentityCandidate( targetCount: 1, showsScore: true, "
                + "showsBestTime: true, rowStyle: .reducedCompact )"
        ))
        XCTAssertLessThan(
            fullHeaderCandidate.lowerBound,
            completeReducedCandidate.lowerBound
        )
        XCTAssertLessThan(
            completeReducedCandidate.lowerBound,
            firstOneTargetFallback.lowerBound
        )

        let compactCandidates = reducedCandidateArguments(in: compactBranch)
        XCTAssertEqual(compactCandidates, [
            "targetCount: 2, showsScore: true, showsBestTime: true, rowStyle: .reducedCompact",
            "targetCount: 1, showsScore: true, showsBestTime: true, rowStyle: .reducedCompact",
            "targetCount: 1, showsScore: true, showsBestTime: false, rowStyle: .reducedCompact",
            "targetCount: 1, showsScore: false, showsBestTime: false, rowStyle: .reducedCompact"
        ])
        XCTAssertFalse(compactCandidates.contains(where: { $0.contains(
            "targetCount: 2, showsScore: true, showsBestTime: false"
        ) }))
        XCTAssertFalse(compactCandidates.contains(where: { $0.contains(
            "targetCount: 2, showsScore: false, showsBestTime: false"
        ) }))

        let minimalBranch = try sourceSection(
            in: source,
            from: "case .minimal:",
            through: ".frame(maxWidth: .infinity, maxHeight:"
        )
        XCTAssertEqual(reducedCandidateArguments(in: minimalBranch), [
            "targetCount: 1, showsScore: true, showsBestTime: true, rowStyle: .minimal",
            "targetCount: 1, showsScore: true, showsBestTime: false, rowStyle: .minimal",
            "targetCount: 1, showsScore: false, showsBestTime: false, rowStyle: .minimal"
        ])

        let identityLabelSection = try sourceSection(
            in: source,
            from: "private func reducedIdentityLabel(",
            through: "private func content("
        )
        let normalizedIdentityLabel = normalizedSource(identityLabelSection)
        XCTAssertTrue(normalizedIdentityLabel.contains(
            "case .regular, .reducedCompact: Text(\"Tonight’s Targets\")"
        ))
        XCTAssertTrue(normalizedIdentityLabel.contains(
            "case .minimal: Text(\"Tonight\")"
        ))
    }

    func testPhaseTwoWidgetPresentationUsesSparklesExclusively() throws {
        let entryViewSource = try sourceText(
            "Sources/Widgets/TonightTargetsWidgetMediumEntryView.swift"
        )
        let widgetSource = try sourceText(
            "Sources/Widgets/TonightTargetsWidget.swift"
        )
        let fullHeaderSection = try sourceSection(
            in: entryViewSource,
            from: "private func header(",
            through: "private func targetRow("
        )
        let reducedIdentitySection = try sourceSection(
            in: entryViewSource,
            from: "private func reducedIdentityCandidate(",
            through: "private func reducedIdentityLabel("
        )

        XCTAssertTrue(entryViewSource.contains(
            "Image(systemName: WidgetAppIdentity.symbol)"
        ))
        XCTAssertTrue(fullHeaderSection.contains(
            "Image(systemName: WidgetAppIdentity.symbol)"
        ))
        XCTAssertTrue(reducedIdentitySection.contains(
            "Image(systemName: WidgetAppIdentity.symbol)"
        ))
        XCTAssertTrue(widgetSource.contains(
            "Label(\"Tonight’s Targets\", systemImage: WidgetAppIdentity.symbol)"
        ))

        for source in [entryViewSource, widgetSource] {
            XCTAssertFalse(source.contains("Image(systemName: \"scope\")"))
            XCTAssertFalse(source.contains("systemImage: \"scope\""))
        }
    }

    func testReducedCompactTypographyIsNarrowlyScoped() throws {
        let source = try sourceText(
            "Sources/Widgets/TonightTargetsWidgetMediumEntryView.swift"
        )
        let normalized = normalizedSource(source)

        XCTAssertTrue(source.contains("case reducedCompact"))
        XCTAssertTrue(normalized.contains(
            "case .reducedCompact: return .caption.weight(.semibold)"
        ))
        XCTAssertTrue(normalized.contains(
            "case .reducedCompact: return .caption.weight(.bold)"
        ))
        XCTAssertTrue(normalized.contains(
            "case .reducedCompact, .minimal: return .caption2"
        ))
        XCTAssertTrue(normalized.contains(
            "case .regular: return .subheadline.weight(.semibold)"
        ))
        XCTAssertTrue(normalized.contains(
            "case .regular: return .subheadline.weight(.bold)"
        ))
        XCTAssertTrue(normalized.contains(
            "case .regular: return .caption"
        ))
        XCTAssertFalse(source.contains(".minimumScaleFactor"))
        XCTAssertFalse(source.contains(".system(size:"))
    }

    func testHourlyTimelineCadenceAndReloadKindsAreExplicit() throws {
        let phaseOneProvider = try sourceText(
            "Sources/Widgets/NightConditionsTimelineProvider.swift"
        )
        let targetsProvider = try sourceText(
            "Sources/Widgets/TonightTargetsTimelineProvider.swift"
        )
        let reloadService = try sourceText(
            "Sources/SharedCode/Core/Services/WidgetReloadService.swift"
        )
        XCTAssertTrue(phaseOneProvider.contains(
            "timelineReevaluationInterval: TimeInterval = 3600"
        ))
        XCTAssertTrue(phaseOneProvider.contains("SharedConditionsRepository"))
        XCTAssertTrue(phaseOneProvider.contains("WidgetNightSummaryPublisher.makeEnriched"))
        XCTAssertTrue(phaseOneProvider.contains("CrossSurfaceLocationContext.make(from: location)"))
        XCTAssertTrue(phaseOneProvider.contains("saveWidgetNightSummaryAsync"))
        XCTAssertTrue(phaseOneProvider.contains("context.isPreview"))
        XCTAssertTrue(phaseOneProvider.contains("fallbackMaximumAge: TimeInterval = 24 * 3600"))
        XCTAssertTrue(phaseOneProvider.contains("Using matching last-known-good Night Conditions summary"))
        XCTAssertFalse(phaseOneProvider.contains("widgetCacheMaxAge"))
        XCTAssertTrue(targetsProvider.contains(
            "timelineReevaluationInterval: TimeInterval = 3600"
        ))
        XCTAssertTrue(reloadService.contains("\"NightConditionsWidget\""))
        XCTAssertTrue(reloadService.contains("\"TonightTargetsWidget\""))

        let conditionsCall = try XCTUnwrap(
            phaseOneProvider.range(of: "conditionsRepository.conditions")
        )
        let fallbackCheck = try XCTUnwrap(
            phaseOneProvider.range(of: "within: Self.fallbackMaximumAge")
        )
        XCTAssertLessThan(
            phaseOneProvider.distance(from: phaseOneProvider.startIndex, to: conditionsCall.lowerBound),
            phaseOneProvider.distance(from: phaseOneProvider.startIndex, to: fallbackCheck.lowerBound)
        )
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func date(day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: day,
            hour: hour
        ))!
    }

    private func makeSummary(
        generatedAt: Date? = nil,
        latitude: Double = 45.5,
        savedLocationID: UUID? = nil,
        observingDate: Date? = nil,
        nightStart: Date? = nil,
        nightEnd: Date? = nil,
        status: WidgetTonightTargetsStatus = .available,
        targets: [WidgetTonightTargetSummary]? = nil
    ) -> WidgetTonightTargetsSummary {
        WidgetTonightTargetsSummary(
            generatedAt: generatedAt ?? date(day: 25, hour: 20),
            locationName: "Home",
            latitude: latitude,
            longitude: -122.7,
            savedLocationID: savedLocationID,
            timeZoneIdentifier: timeZone.identifier,
            observingDate: observingDate ?? date(day: 25),
            astronomicalNightStart: nightStart ?? date(day: 25, hour: 22),
            astronomicalNightEnd: nightEnd ?? date(day: 26, hour: 4),
            status: status,
            targets: targets ?? [makeTarget()]
        )
    }

    private func makeTarget(
        name: String = "NGC 869/884 Double Cluster"
    ) -> WidgetTonightTargetSummary {
        WidgetTonightTargetSummary(
            targetID: "double-cluster",
            displayName: name,
            categoryLabel: "Open Cluster Pair",
            score: 91,
            scoreTone: .positive,
            bestTime: date(day: 25, hour: 23),
            positionLabel: "NE · 62°"
        )
    }

    private func makeConditions(
        referenceDate: Date,
        includesForecasts: Bool = true,
        dataStartDay: Int = 25,
        locationID: UUID? = nil
    ) -> ViewingConditions {
        let start = date(day: dataStartDay)
        let forecasts = includesForecasts ? (0..<(4 * 24)).map { offset in
            HourlyForecast(
                time: start.addingTimeInterval(TimeInterval(offset) * 3600),
                cloudCover: 20 + offset % 10,
                humidity: 45,
                windSpeed: 2,
                windDirection: 180,
                temperature: 12,
                dewPoint: 5,
                visibility: 20_000
            )
        } : []
        let sunEvents = (0...3).map { offset in
            let day = dataStartDay + offset
            return SunEvents(
                sunrise: date(day: day, hour: 6),
                sunset: date(day: day, hour: 20),
                civilTwilightBegin: date(day: day, hour: 5),
                civilTwilightEnd: date(day: day, hour: 21),
                nauticalTwilightBegin: date(day: day, hour: 4),
                nauticalTwilightEnd: date(day: day, hour: 21),
                astronomicalTwilightBegin: date(day: day, hour: 4),
                astronomicalTwilightEnd: date(day: day, hour: 22)
            )
        }

        return ViewingConditions(
            fetchedAt: referenceDate,
            location: CachedLocation(
                id: locationID,
                name: "Home",
                latitude: 45.5,
                longitude: -122.7
            ),
            hourlyForecasts: forecasts,
            dailySunEvents: sunEvents,
            dailyMoonInfo: (0...3).map {
                MoonInfo(
                    phase: 0.2,
                    phaseName: "Waxing",
                    altitude: 10,
                    illumination: 20 + $0,
                    emoji: "🌒"
                )
            },
            issPasses: [],
            fogScore: FogScore(score: 0, factors: []),
            timeZoneIdentifier: timeZone.identifier
        )
    }

    private func makeRecommendation(id: String, score: Int) -> TargetRecommendation {
        TargetRecommendation(
            target: ObservableTarget(
                id: id,
                name: id.capitalized,
                type: .deepSky,
                preferredEquipment: .binoculars,
                difficulty: 0.5,
                observingIntent: .standard,
                deepSkyObjectType: .openCluster
            ),
            score: score,
            visibilityWindow: TargetVisibilityWindow(
                start: date(day: 25, hour: 22),
                end: date(day: 26, hour: 4),
                bestTime: date(day: 25, hour: 23),
                maxAltitude: 48,
                direction: "SW"
            ),
            reasons: [.highAltitude],
            summary: "Resolved recommendation"
        )
    }

    private func selectUnavailableEntry(
        existing: WidgetTonightTargetsSummary?,
        referenceDate: Date
    ) -> TonightTargetsUnavailableEntrySelection {
        let candidate = makeSummary(
            generatedAt: referenceDate,
            status: .unavailable,
            targets: []
        )
        return TonightTargetsUnavailableEntrySelector.select(
            candidate: candidate,
            existing: existing,
            targetLocation: CachedLocation(
                name: "Home",
                latitude: 45.5,
                longitude: -122.7
            ),
            referenceDate: referenceDate,
            candidateDataStatus: .normal(summary: candidate)
        )
    }

    private func assertUnavailableCandidateSelected(
        _ selection: TonightTargetsUnavailableEntrySelection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(selection.shouldSaveCandidate, file: file, line: line)
        XCTAssertEqual(
            selection.displayedSummary.status,
            .unavailable,
            file: file,
            line: line
        )
        guard case .unavailable(.unavailable) = selection.entry.state else {
            return XCTFail(
                "Expected unavailable candidate to be displayed",
                file: file,
                line: line
            )
        }
    }

    private func sourceText(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func sourceSection(
        in source: String,
        from startMarker: String,
        through endMarker: String
    ) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMarker)?.lowerBound)
        let end = try XCTUnwrap(
            source.range(of: endMarker, range: start..<source.endIndex)?.upperBound
        )
        return String(source[start..<end])
    }

    private func normalizedSource(_ source: String) -> String {
        source
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func reducedCandidateArguments(in source: String) -> [String] {
        let marker = "reducedIdentityCandidate("
        var arguments: [String] = []
        var searchStart = source.startIndex

        while let markerRange = source.range(
            of: marker,
            range: searchStart..<source.endIndex
        ), let closingParenthesis = source.range(
            of: ")",
            range: markerRange.upperBound..<source.endIndex
        ) {
            arguments.append(normalizedSource(String(
                source[markerRange.upperBound..<closingParenthesis.lowerBound]
            )))
            searchStart = closingParenthesis.upperBound
        }

        return arguments
    }

    private func contentCandidateArguments(in source: String) -> [String] {
        let marker = "content("
        var arguments: [String] = []
        var searchStart = source.startIndex

        while let markerRange = source.range(
            of: marker,
            range: searchStart..<source.endIndex
        ), let closingParenthesis = source.range(
            of: ")",
            range: markerRange.upperBound..<source.endIndex
        ) {
            arguments.append(normalizedSource(String(
                source[markerRange.upperBound..<closingParenthesis.lowerBound]
            )))
            searchStart = closingParenthesis.upperBound
        }

        return arguments
    }
}

private final class RecordingRecommendationService:
    TargetRecommendationProviding,
    @unchecked Sendable
{
    private(set) var contexts: [TargetRecommendationContext] = []
    private(set) var requestedLimits: [Int] = []

    func recommendations(
        for context: TargetRecommendationContext,
        limit: Int
    ) -> [TargetRecommendation] {
        contexts.append(context)
        requestedLimits.append(limit)
        return []
    }
}

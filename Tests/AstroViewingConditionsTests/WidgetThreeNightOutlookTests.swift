import Foundation
import SwiftUI
import XCTest
@testable import AstroViewingConditions
@testable import SharedCode

final class WidgetThreeNightOutlookTests: XCTestCase {
    private let timeZone = TimeZone(identifier: "America/Los_Angeles")!

    func testDayRolloverFailedRefreshRebuildsFromRetainedConditionsWithPartialThirdNight() async throws {
        let referenceDate = date(day: 26, hour: 6)
        let location = selectedLocation()
        let cachedSummary = makeSummary(
            generatedAt: date(day: 25, hour: 20),
            nights: shiftedNights(startDay: 25)
        )
        let retainedConditions = makeFourCalendarDayHourlyConditions(
            referenceDate: referenceDate,
            fetchedAt: date(day: 26, hour: 5, minute: 30)
        )
        let fetchAttempts = FetchAttemptRecorder()
        let saves = SummaryRecorder()
        let cachedLocation = CachedLocation(
            name: location.name,
            latitude: location.latitude,
            longitude: location.longitude
        )
        let entry = await ThreeNightOutlookEntryResolver.buildEntry(
            location: location,
            cachedSummary: cachedSummary,
            cachedLocation: cachedLocation,
            referenceDate: referenceDate,
            normalConditions: {
                await fetchAttempts.record()
                throw DayRolloverRefreshError.failed
            },
            retainedConditions: { retainedConditions },
            save: { summary in await saves.record(summary) }
        )
        let attempts = await fetchAttempts.total()
        XCTAssertEqual(attempts, 1)
        guard case let .available(rebuiltSummary) = entry.state else {
            return XCTFail("Expected retained conditions to rebuild the widget")
        }
        XCTAssertEqual(
            rebuiltSummary.nights.map(\.observingDate),
            [date(day: 26), date(day: 27), date(day: 28)]
        )
        XCTAssertTrue(rebuiltSummary.nights.prefix(2).allSatisfy {
            $0.status == .available && $0.score != nil
        })
        let third = try XCTUnwrap(rebuiltSummary.nights.last)
        XCTAssertEqual(third.status, .unavailable)
        XCTAssertNil(third.score)
        XCTAssertNil(third.bestWindow)
        XCTAssertEqual(third.verdict, "N/A")
        XCTAssertEqual(third.statusText, "Needs fresh data")
        XCTAssertEqual(entry.dataStatus?.provenance, .fallback)
        XCTAssertEqual(entry.dataStatus?.dataAsOf, retainedConditions.fetchedAt)
        let savedSummaries = await saves.values()
        XCTAssertEqual(savedSummaries, [rebuiltSummary])
    }

    func testFourCalendarDayHourlyForecastMarksPartialThirdNightUnavailable() throws {
        let referenceDate = date(day: 26, hour: 6)
        let conditions = makeFourCalendarDayHourlyConditions(
            referenceDate: referenceDate
        )
        XCTAssertEqual(conditions.hourlyForecasts.first?.time, date(day: 25))
        XCTAssertEqual(conditions.hourlyForecasts.last?.time, date(day: 28, hour: 23))
        XCTAssertEqual(conditions.hourlyForecasts.count, 4 * 24)

        let resolutions = try XCTUnwrap((0..<3).map { dayOffset in
            TargetRecommendationContextBuilder.resolve(
                conditions: conditions,
                dayOffset: dayOffset,
                referenceDate: referenceDate,
                timeZone: timeZone
            )
        }.compactMap { $0 })
        XCTAssertEqual(resolutions.count, 3)

        let coverage = resolutions.map(hourlyCoverage(for:))
        XCTAssertEqual(coverage.map(\.observingDate), [
            date(day: 26), date(day: 27), date(day: 28)
        ])
        XCTAssertEqual(coverage.map(\.astronomicalNightStart), [
            date(day: 26, hour: 22, minute: 18),
            date(day: 27, hour: 22, minute: 18),
            date(day: 28, hour: 22, minute: 18)
        ])
        XCTAssertEqual(coverage.map(\.astronomicalNightEnd), [
            date(day: 27, hour: 4, minute: 37),
            date(day: 28, hour: 4, minute: 37),
            date(day: 29, hour: 4, minute: 37)
        ])
        XCTAssertEqual(coverage.map(\.firstRelevantHourlyTimestamp), [
            date(day: 26, hour: 23), date(day: 27, hour: 23), date(day: 28, hour: 23)
        ])
        XCTAssertEqual(coverage.map(\.lastRelevantHourlyTimestamp), [
            date(day: 27, hour: 4), date(day: 28, hour: 4), date(day: 28, hour: 23)
        ])
        XCTAssertEqual(coverage.map(\.reachesAstronomicalNightEnd), [true, true, false])

        let decision = ThreeNightOutlookWidgetPayloadBuilder.publicationDecision(
            conditions: conditions,
            existingSummary: nil,
            referenceDate: referenceDate,
            timeZone: timeZone
        )
        guard case let .publish(summary) = decision else {
            return XCTFail("Expected the current payload builder to publish")
        }
        let thirdNight = try XCTUnwrap(summary.nights.last)
        XCTAssertTrue(summary.nights.prefix(2).allSatisfy {
            $0.status == .available && $0.score != nil
        })
        XCTAssertEqual(thirdNight.status, .unavailable)
        XCTAssertNil(thirdNight.score)
        XCTAssertNil(thirdNight.bestWindow)
        XCTAssertEqual(thirdNight.verdict, "N/A")
        XCTAssertEqual(thirdNight.statusText, "Needs fresh data")
    }

    func testHourlyCoverageThroughThirdDawnScoresAllThreeNights() throws {
        let referenceDate = date(day: 26, hour: 6)
        let conditions = makeFourCalendarDayHourlyConditions(
            referenceDate: referenceDate,
            hourlyDayCount: 5
        )
        let decision = ThreeNightOutlookWidgetPayloadBuilder.publicationDecision(
            conditions: conditions, existingSummary: nil,
            referenceDate: referenceDate, timeZone: timeZone
        )
        guard case let .publish(summary) = decision else {
            return XCTFail("Expected a published outlook")
        }
        XCTAssertTrue(summary.nights.allSatisfy {
            $0.status == .available && $0.score != nil && $0.bestWindow != nil
        })
    }

    func testMissingHourlyIntervalMarksOnlyThatNightUnavailable() throws {
        let referenceDate = date(day: 26, hour: 6)
        let conditions = makeFourCalendarDayHourlyConditions(
            referenceDate: referenceDate,
            hourlyDayCount: 5,
            missingHours: [date(day: 27, hour: 1)]
        )
        let decision = ThreeNightOutlookWidgetPayloadBuilder.publicationDecision(
            conditions: conditions, existingSummary: nil,
            referenceDate: referenceDate, timeZone: timeZone
        )
        guard case let .publish(summary) = decision else {
            return XCTFail("Expected a published outlook")
        }
        XCTAssertEqual(summary.nights[0].status, .unavailable)
        XCTAssertNil(summary.nights[0].score)
        XCTAssertEqual(summary.nights[0].statusText, "Needs fresh data")
        XCTAssertTrue(summary.nights.dropFirst().allSatisfy { $0.status == .available })
    }

    func testZeroHourlySamplesWithAstronomicalNightMarksNightUnavailable() throws {
        let referenceDate = date(day: 26, hour: 6)
        let conditions = makeFourCalendarDayHourlyConditions(
            referenceDate: referenceDate,
            missingHours: [date(day: 28, hour: 22), date(day: 28, hour: 23)]
        )
        let decision = ThreeNightOutlookWidgetPayloadBuilder.publicationDecision(
            conditions: conditions, existingSummary: nil,
            referenceDate: referenceDate, timeZone: timeZone
        )
        guard case let .publish(summary) = decision,
              let third = summary.nights.last else {
            return XCTFail("Expected a three-night summary")
        }
        XCTAssertNotNil(third.astronomicalNightStart)
        XCTAssertNotNil(third.astronomicalNightEnd)
        XCTAssertEqual(third.status, .unavailable)
        XCTAssertNil(third.score)
        XCTAssertNil(third.bestWindow)
        XCTAssertNil(third.scoreTone)
        XCTAssertEqual(third.verdict, "N/A")
        XCTAssertEqual(third.statusText, "Needs fresh data")
        XCTAssertFalse(third.isBestNight)
    }

    func testInvalidAstronomicalNightBoundariesKeepNoAstronomicalNightBehavior() throws {
        let referenceDate = date(day: 26, hour: 6)
        let decision = ThreeNightOutlookWidgetPayloadBuilder.publicationDecision(
            conditions: makeConditions(
                referenceDate: referenceDate,
                dataStartDay: 25,
                dailyCount: 4
            ),
            existingSummary: nil,
            referenceDate: referenceDate,
            timeZone: timeZone
        )
        guard case let .publish(summary) = decision,
              let third = summary.nights.last else {
            return XCTFail("Expected a three-night summary")
        }
        XCTAssertEqual(third.status, .noAstronomicalNight)
        XCTAssertEqual(third.verdict, "No night")
        XCTAssertEqual(third.statusText, "No astronomical night")
    }

    func testWrongLocationRetainedConditionsAreNotUsed() async {
        let referenceDate = date(day: 26, hour: 6)
        let location = selectedLocation()
        let cachedSummary = makeSummary(nights: shiftedNights(startDay: 25))
        let wrongLocationConditions = makeFourCalendarDayHourlyConditions(
            referenceDate: referenceDate,
            fetchedAt: date(day: 25, hour: 23),
            location: CachedLocation(name: "Elsewhere", latitude: 47.6, longitude: -122.7)
        )
        let entry = await ThreeNightOutlookEntryResolver.buildEntry(
            location: location,
            cachedSummary: cachedSummary,
            cachedLocation: CachedLocation(name: location.name, latitude: location.latitude, longitude: location.longitude),
            referenceDate: referenceDate,
            normalConditions: { throw DayRolloverRefreshError.failed },
            retainedConditions: { wrongLocationConditions },
            save: { _ in }
        )
        guard case let .unavailable(reason) = entry.state else {
            return XCTFail("Wrong-location retained conditions must not be displayed")
        }
        XCTAssertEqual(reason, .stale)
    }

    func testNoRetainedConditionsKeepsNoCacheUnavailableBehavior() async {
        let referenceDate = date(day: 26, hour: 6)
        let location = selectedLocation()
        let entry = await ThreeNightOutlookEntryResolver.buildEntry(
            location: location,
            cachedSummary: nil,
            cachedLocation: CachedLocation(name: location.name, latitude: location.latitude, longitude: location.longitude),
            referenceDate: referenceDate,
            normalConditions: { throw DayRolloverRefreshError.failed },
            retainedConditions: { nil },
            save: { _ in }
        )
        guard case let .unavailable(reason) = entry.state else {
            return XCTFail("Expected no-cache unavailable state")
        }
        XCTAssertEqual(reason, .noCache)
    }

    func testNormalPublicationValidatesAtPostWorkDateWhileBuildingForTimelineReference() async {
        let timelineReferenceDate = date(day: 26, hour: 1)
        let fetchedAt = timelineReferenceDate.addingTimeInterval(2)
        let validationDate = timelineReferenceDate.addingTimeInterval(3)
        let location = selectedLocation()
        let conditions = makeConditions(
            referenceDate: timelineReferenceDate,
            fetchedAt: fetchedAt,
            dataStartDay: 25
        )
        let saves = SummaryRecorder()

        let entry = await ThreeNightOutlookEntryResolver.buildEntry(
            location: location,
            cachedSummary: nil,
            cachedLocation: CachedLocation(
                name: location.name,
                latitude: location.latitude,
                longitude: location.longitude
            ),
            referenceDate: timelineReferenceDate,
            normalConditions: { conditions },
            retainedConditions: { nil },
            save: { summary in await saves.record(summary) },
            postWorkValidationDate: { validationDate }
        )

        guard case let .available(summary) = entry.state else {
            return XCTFail("A just-fetched summary must remain available")
        }
        XCTAssertEqual(summary.generatedAt, fetchedAt)
        XCTAssertEqual(summary.nights.first?.observingDate, date(day: 25))
        XCTAssertEqual(entry.date, validationDate)
        XCTAssertEqual(
            ThreeNightOutlookEntryResolver.resolve(
                summary: summary,
                selectedLocation: location,
                referenceDate: validationDate
            ),
            .available
        )
        XCTAssertEqual(
            ThreeNightOutlookEntryResolver.resolve(
                summary: summary,
                selectedLocation: location,
                referenceDate: timelineReferenceDate
            ),
            .stale,
            "This is the former negative-age failure"
        )
        let savedSummaries = await saves.values()
        XCTAssertEqual(savedSummaries, [summary])
    }

    func testRetainedPublicationUsesPostWorkEntryDateAndRemainsAvailable() async {
        let timelineReferenceDate = date(day: 26, hour: 6)
        let validationDate = timelineReferenceDate.addingTimeInterval(3)
        let location = selectedLocation()
        let retained = makeFourCalendarDayHourlyConditions(
            referenceDate: timelineReferenceDate,
            fetchedAt: timelineReferenceDate.addingTimeInterval(-2)
        )

        let entry = await ThreeNightOutlookEntryResolver.buildEntry(
            location: location,
            cachedSummary: nil,
            cachedLocation: CachedLocation(
                name: location.name,
                latitude: location.latitude,
                longitude: location.longitude
            ),
            referenceDate: timelineReferenceDate,
            normalConditions: { throw DayRolloverRefreshError.failed },
            retainedConditions: { retained },
            save: { _ in },
            postWorkValidationDate: { validationDate }
        )

        guard case let .available(summary) = entry.state else {
            return XCTFail("Recent retained conditions must remain available")
        }
        XCTAssertEqual(summary.generatedAt, timelineReferenceDate.addingTimeInterval(-2))
        XCTAssertEqual(entry.date, validationDate)
        XCTAssertEqual(entry.dataStatus?.provenance, .fallback)
    }

    func testRetainedPublicationGeneratedMeaningfullyAfterValidationIsRejected() async {
        let timelineReferenceDate = date(day: 26, hour: 6)
        let validationDate = timelineReferenceDate.addingTimeInterval(3)
        let location = selectedLocation()
        let retained = makeFourCalendarDayHourlyConditions(
            referenceDate: timelineReferenceDate,
            fetchedAt: validationDate.addingTimeInterval(3600)
        )
        let saves = SummaryRecorder()
        var loggedContext: ThreeNightOutlookUnavailableLogContext?

        let entry = await ThreeNightOutlookEntryResolver.buildEntry(
            location: location,
            cachedSummary: nil,
            cachedLocation: CachedLocation(
                name: location.name,
                latitude: location.latitude,
                longitude: location.longitude
            ),
            referenceDate: timelineReferenceDate,
            normalConditions: { throw DayRolloverRefreshError.failed },
            retainedConditions: { retained },
            save: { summary in await saves.record(summary) },
            postWorkValidationDate: { validationDate },
            logUnavailable: { loggedContext = $0 }
        )

        guard case let .unavailable(reason) = entry.state else {
            return XCTFail("Future-dated retained publication must be rejected")
        }
        XCTAssertEqual(reason, .stale)
        XCTAssertEqual(entry.date, validationDate)
        XCTAssertEqual(loggedContext?.stage, "presentationAge")
        XCTAssertEqual(loggedContext?.path, "retained")
        XCTAssertEqual(loggedContext?.age ?? 0, -3600, accuracy: 0.001)
        let savedSummaries = await saves.values()
        XCTAssertEqual(savedSummaries.count, 1, "Save behavior must remain unchanged")
    }

    func testRetainedPublicationAtPresentationAgeLimitIsRejected() async {
        let timelineReferenceDate = date(day: 26, hour: 6)
        let validationDate = timelineReferenceDate.addingTimeInterval(3)
        let location = selectedLocation()
        let retained = makeFourCalendarDayHourlyConditions(
            referenceDate: timelineReferenceDate,
            fetchedAt: validationDate.addingTimeInterval(
                -WidgetThreeNightOutlookSummary.maximumAge
            )
        )
        var loggedContext: ThreeNightOutlookUnavailableLogContext?

        let entry = await ThreeNightOutlookEntryResolver.buildEntry(
            location: location,
            cachedSummary: nil,
            cachedLocation: CachedLocation(
                name: location.name,
                latitude: location.latitude,
                longitude: location.longitude
            ),
            referenceDate: timelineReferenceDate,
            normalConditions: { throw DayRolloverRefreshError.failed },
            retainedConditions: { retained },
            save: { _ in },
            postWorkValidationDate: { validationDate },
            logUnavailable: { loggedContext = $0 }
        )

        guard case let .unavailable(reason) = entry.state else {
            return XCTFail("Retained publication at the one-hour limit must be rejected")
        }
        XCTAssertEqual(reason, .stale)
        XCTAssertEqual(entry.date, validationDate)
        XCTAssertEqual(loggedContext?.stage, "presentationAge")
        XCTAssertEqual(loggedContext?.path, "retained")
        XCTAssertEqual(
            loggedContext?.age ?? 0,
            WidgetThreeNightOutlookSummary.maximumAge,
            accuracy: 0.001
        )
    }

    func testMeaningfullyFutureDatedCachedSummaryRemainsRejected() {
        let validationDate = date(day: 26, hour: 1)
        var loggedContext: ThreeNightOutlookUnavailableLogContext?
        let entry = ThreeNightOutlookEntryResolver.failedRefreshEntry(
            cachedSummary: makeSummary(
                generatedAt: validationDate.addingTimeInterval(3600),
                nights: shiftedNights(startDay: 25)
            ),
            selectedLocation: selectedLocation(),
            referenceDate: validationDate,
            fetchFailureCategory: "test-failure",
            logUnavailable: { loggedContext = $0 }
        )

        guard case let .unavailable(reason) = entry.state else {
            return XCTFail("Future-dated cache must remain rejected")
        }
        XCTAssertEqual(reason, .stale)
        XCTAssertEqual(loggedContext?.stage, "fallbackAge")
        XCTAssertEqual(loggedContext?.path, "rejectedCache")
        XCTAssertEqual(loggedContext?.fetchFailureCategory, "test-failure")
        XCTAssertEqual(loggedContext?.age ?? 0, -3600, accuracy: 0.001)
    }

    func testActiveNightCachedSummaryRemainsFallbackAfterRetainedRebuildCannotPublish() async {
        let referenceDate = date(day: 26, hour: 1)
        let location = selectedLocation()
        let cachedSummary = makeSummary(
            generatedAt: referenceDate,
            nights: shiftedNights(startDay: 25)
        )
        let incompleteRetained = makeConditions(
            referenceDate: referenceDate,
            fetchedAt: date(day: 25, hour: 23),
            dataStartDay: 25,
            dailyCount: 2
        )
        let entry = await ThreeNightOutlookEntryResolver.buildEntry(
            location: location,
            cachedSummary: cachedSummary,
            cachedLocation: CachedLocation(name: location.name, latitude: location.latitude, longitude: location.longitude),
            referenceDate: referenceDate,
            normalConditions: { throw DayRolloverRefreshError.failed },
            retainedConditions: { incompleteRetained },
            save: { _ in }
        )
        guard case let .available(summary) = entry.state else {
            return XCTFail("Expected active cached summary fallback")
        }
        XCTAssertEqual(summary, cachedSummary)
        XCTAssertEqual(entry.dataStatus?.provenance, .fallback)
    }

    func testUnavailablePublicationUsesBoundedLastKnownGoodSummaryWithoutSaving() async {
        let referenceDate = date(day: 26, hour: 1)
        let location = selectedLocation()
        let cachedSummary = makeSummary(
            generatedAt: date(day: 25, hour: 20),
            nights: shiftedNights(startDay: 25)
        )
        let saves = SummaryRecorder()
        let entry = await ThreeNightOutlookEntryResolver.buildEntry(
            location: location,
            cachedSummary: cachedSummary,
            cachedLocation: CachedLocation(name: location.name, latitude: location.latitude, longitude: location.longitude),
            referenceDate: referenceDate,
            normalConditions: {
                makeConditions(
                    referenceDate: referenceDate,
                    dataStartDay: 25,
                    dailyCount: 2
                )
            },
            retainedConditions: { nil },
            save: { summary in await saves.record(summary) }
        )
        XCTAssertTrue(cachedSummary.isDataBearing)
        guard case let .available(summary) = entry.state else {
            return XCTFail("Expected valid active cached summary to remain visible")
        }
        XCTAssertEqual(summary, cachedSummary)
        XCTAssertEqual(entry.dataStatus?.provenance, .fallback)
        XCTAssertEqual(entry.dataStatus?.dataAsOf, cachedSummary.generatedAt)
        let savedSummaries = await saves.values()
        XCTAssertTrue(savedSummaries.isEmpty)
    }

    func testUnavailablePublicationDoesNotDisplayInvalidPreviousNightSummary() async {
        let referenceDate = date(day: 26, hour: 6)
        let location = selectedLocation()
        let cachedSummary = makeSummary(
            generatedAt: referenceDate,
            nights: shiftedNights(startDay: 25)
        )
        let saves = SummaryRecorder()
        let entry = await ThreeNightOutlookEntryResolver.buildEntry(
            location: location,
            cachedSummary: cachedSummary,
            cachedLocation: CachedLocation(name: location.name, latitude: location.latitude, longitude: location.longitude),
            referenceDate: referenceDate,
            normalConditions: {
                makeConditions(referenceDate: referenceDate, dataStartDay: 25, dailyCount: 2)
            },
            retainedConditions: { nil },
            save: { summary in await saves.record(summary) }
        )
        guard case .unavailable = entry.state else {
            return XCTFail("Previous-night cached summary must not be relabeled as current")
        }
        let savedSummaries = await saves.values()
        XCTAssertTrue(savedSummaries.isEmpty)
    }

    func testUnavailablePublicationRejectsInvalidLastKnownGoodSummaries() async {
        let referenceDate = date(day: 26, hour: 1)
        let validNights = shiftedNights(startDay: 25)
        var malformedNights = validNights
        malformedNights.swapAt(0, 1)
        let invalidSummaries = [
            makeSummary(generatedAt: date(day: 24, hour: 0), nights: validNights),
            makeSummary(generatedAt: date(day: 25, hour: 20), latitude: 47.6, nights: validNights),
            makeSummary(generatedAt: date(day: 25, hour: 20), nights: shiftedNights(startDay: 24)),
            makeSummary(generatedAt: date(day: 25, hour: 20), nights: malformedNights),
            makeSummary(
                generatedAt: date(day: 25, hour: 20),
                nights: validNights.map { night in
                    self.night(
                        label: night.displayLabel,
                        day: calendar.component(.day, from: night.observingDate),
                        score: nil,
                        status: .available,
                        isBest: false
                    )
                }
            )
        ]

        for summary in invalidSummaries {
            let entry = await unavailablePublicationEntry(
                cachedSummary: summary,
                referenceDate: referenceDate
            )
            guard case .unavailable = entry.state else {
                return XCTFail("Invalid last-known-good summary must not remain visible")
            }
        }
    }

    func testUnavailablePublicationWithoutDataBearingCacheMaySaveUnavailableSummary() async {
        let referenceDate = date(day: 25, hour: 20)
        let location = selectedLocation()
        let saves = SummaryRecorder()
        let entry = await ThreeNightOutlookEntryResolver.buildEntry(
            location: location,
            cachedSummary: nil,
            cachedLocation: CachedLocation(name: location.name, latitude: location.latitude, longitude: location.longitude),
            referenceDate: referenceDate,
            normalConditions: { makeConditions(referenceDate: referenceDate, dailyCount: 2) },
            retainedConditions: { nil },
            save: { summary in await saves.record(summary) }
        )
        guard case .unavailable = entry.state else {
            return XCTFail("Expected unavailable result without a data-bearing cache")
        }
        let savedSummaries = await saves.values()
        XCTAssertEqual(savedSummaries.count, 1)
        XCTAssertEqual(savedSummaries.first?.status, .unavailable)
    }

    func testPayloadJSONRoundTrip() throws {
        let summary = makeSummary()
        let encoded = try JSONEncoder().encode(summary)
        XCTAssertEqual(
            try JSONDecoder().decode(
                WidgetThreeNightOutlookSummary.self,
                from: encoded
            ),
            summary
        )

        var legacyPayload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        legacyPayload.removeValue(forKey: "savedLocationID")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyPayload)
        XCTAssertNil(try JSONDecoder().decode(
            WidgetThreeNightOutlookSummary.self,
            from: legacyData
        ).savedLocationID)
    }

    func testSeparateCacheFilenameAtomicReplacementAndMissingCache() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertNil(AppGroupStorage.readWidgetThreeNightOutlookSummary(baseURL: directory))
        XCTAssertTrue(AppGroupStorage.writeWidgetThreeNightOutlookSummary(makeSummary(), baseURL: directory))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("widgetThreeNightOutlook.json").path
        ))
        let replacement = makeSummary(locationName: "Replacement")
        XCTAssertTrue(AppGroupStorage.writeWidgetThreeNightOutlookSummary(replacement, baseURL: directory))
        XCTAssertEqual(
            AppGroupStorage.readWidgetThreeNightOutlookSummary(baseURL: directory),
            replacement
        )
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("widgetTonightTargets.json").path
        ))
    }

    func testMaximumAgeMatchesConditionsCacheAndRejectsOlderSummary() {
        let generatedAt = date(day: 25, hour: 20)
        let summary = makeSummary(generatedAt: generatedAt)
        let maximumAge = WidgetThreeNightOutlookSummary.maximumAge

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

    func testLocationMatchAndMismatch() {
        let summary = makeSummary()
        XCTAssertTrue(summary.locationMatches(latitude: 45.5, longitude: -122.7))
        XCTAssertFalse(summary.locationMatches(latitude: 47.6, longitude: -122.7))
    }

    func testSavedLocationIdentityRejectsNearbyDifferentSiteAndAcceptsSameSite() {
        let firstID = UUID()
        let summary = makeSummary(savedLocationID: firstID)

        XCTAssertFalse(summary.locationMatches(selectedLocation(
            id: UUID(), latitude: 45.500001, longitude: -122.699999, source: .saved
        )))
        XCTAssertTrue(summary.locationMatches(selectedLocation(
            id: firstID, latitude: 46.0, longitude: -123.0, source: .saved
        )))
        XCTAssertFalse(summary.locationMatches(selectedLocation(
            latitude: 45.5, longitude: -122.7, source: .currentGPS
        )))
        XCTAssertFalse(summary.locationMatches(CachedLocation(
            name: "Current Location", latitude: 45.5, longitude: -122.7
        )))
    }

    func testLegacySummaryUsesStrictCoordinateFallback() {
        let summary = makeSummary()
        XCTAssertTrue(summary.locationMatches(selectedLocation()))
        XCTAssertFalse(summary.locationMatches(selectedLocation(latitude: 45.50002)))
        XCTAssertFalse(summary.locationMatches(selectedLocation(id: UUID(), source: .saved)))
        XCTAssertFalse(summary.locationMatches(CachedLocation(
            id: UUID(), name: "Home", latitude: 45.5, longitude: -122.7
        )))
    }

    func testExactlyThreeOrderedEntriesRequired() {
        let summary = makeSummary()
        XCTAssertTrue(summary.hasCorrectlyOrderedNights())
        XCTAssertFalse(makeSummary(nights: Array(summary.nights.prefix(2))).hasCorrectlyOrderedNights())
        XCTAssertFalse(makeSummary(nights: summary.nights.reversed()).hasCorrectlyOrderedNights())
    }

    func testActiveNightValidationAcrossMidnight() {
        let summary = makeSummary()
        XCTAssertTrue(summary.matchesCurrentObservingNight(relativeTo: date(day: 25, hour: 14)))
        XCTAssertTrue(summary.matchesCurrentObservingNight(relativeTo: date(day: 26, hour: 1)))
        XCTAssertFalse(summary.matchesCurrentObservingNight(relativeTo: date(day: 26, hour: 5)))
    }

    func testProviderStateResolution() {
        let referenceDate = date(day: 25, hour: 21)
        let location = selectedLocation()
        let valid = makeSummary(generatedAt: referenceDate)

        XCTAssertEqual(resolve(valid, nil, at: referenceDate), .noLocation)
        XCTAssertEqual(resolve(nil, location, at: referenceDate), .noCache)
        XCTAssertEqual(
            resolve(
                makeSummary(
                    generatedAt: referenceDate.addingTimeInterval(
                        -WidgetThreeNightOutlookSummary.maximumAge - 1
                    )
                ),
                location, at: referenceDate
            ),
            .stale
        )
        XCTAssertEqual(
            resolve(makeSummary(generatedAt: referenceDate, latitude: 47.6), location, at: referenceDate),
            .locationMismatch
        )
        XCTAssertEqual(
            resolve(
                makeSummary(
                    generatedAt: referenceDate,
                    nights: shiftedNights(startDay: 24)
                ),
                location, at: referenceDate
            ),
            .observingNightMismatch
        )
        XCTAssertEqual(
            resolve(
                makeSummary(generatedAt: referenceDate, status: .unavailable),
                location, at: referenceDate
            ),
            .unavailable
        )
        XCTAssertEqual(
            resolve(
                makeSummary(generatedAt: referenceDate, nights: Array(valid.nights.prefix(2))),
                location, at: referenceDate
            ),
            .unavailable
        )
        XCTAssertEqual(
            resolve(
                makeSummary(generatedAt: referenceDate, nights: [
                    valid.nights[0], valid.nights[2], valid.nights[1]
                ]),
                location, at: referenceDate
            ),
            .unavailable
        )
        var missingScore = valid.nights
        missingScore[0] = night(
            label: "Tonight", day: 25, score: nil, status: .available, isBest: false
        )
        XCTAssertEqual(
            resolve(
                makeSummary(generatedAt: referenceDate, nights: missingScore),
                location, at: referenceDate
            ),
            .unavailable
        )
        XCTAssertEqual(resolve(valid, location, at: referenceDate), .available)
        XCTAssertEqual(
            resolve(
                makeSummary(generatedAt: referenceDate, savedLocationID: UUID()),
                location,
                at: referenceDate
            ),
            .locationMismatch
        )
        XCTAssertEqual(
            resolve(
                makeSummary(generatedAt: referenceDate),
                selectedLocation(id: UUID(), source: .saved),
                at: referenceDate
            ),
            .locationMismatch
        )
    }

    func testDashboardPreservesUsefulMatchingSummaryYoungerThanTwentyFourHours() {
        let referenceDate = date(day: 25, hour: 20)
        let targetLocation = CachedLocation(name: "Home", latitude: 45.5, longitude: -122.7)
        let existing = makeSummary(generatedAt: date(day: 25, hour: 1))
        let unavailable = ThreeNightOutlookWidgetPayloadBuilder.makeUnavailableSummary(
            generatedAt: referenceDate,
            location: targetLocation,
            timeZone: timeZone,
            referenceDate: referenceDate
        )

        XCTAssertTrue(existing.isDataBearing)
        XCTAssertFalse(ThreeNightOutlookPersistencePolicy.shouldSave(
            decision: .unavailable(unavailable),
            existing: existing,
            targetLocation: targetLocation,
            referenceDate: referenceDate
        ))
        XCTAssertFalse(ThreeNightOutlookPersistencePolicy.shouldSaveUnavailable(
            existing: existing,
            targetLocation: targetLocation,
            referenceDate: referenceDate
        ))
    }

    func testDashboardMayReplaceMatchingSummaryOlderThanTwentyFourHours() {
        let referenceDate = date(day: 26, hour: 2)
        let targetLocation = CachedLocation(name: "Home", latitude: 45.5, longitude: -122.7)
        let existing = makeSummary(generatedAt: date(day: 25, hour: 1))
        let unavailable = ThreeNightOutlookWidgetPayloadBuilder.makeUnavailableSummary(
            generatedAt: referenceDate,
            location: targetLocation,
            timeZone: timeZone,
            referenceDate: referenceDate
        )

        XCTAssertTrue(ThreeNightOutlookPersistencePolicy.shouldSave(
            decision: .unavailable(unavailable),
            existing: existing,
            targetLocation: targetLocation,
            referenceDate: referenceDate
        ))
    }

    func testDashboardAlwaysSavesNewDataBearingPublication() {
        let referenceDate = date(day: 25, hour: 20)
        let targetLocation = CachedLocation(name: "Home", latitude: 45.5, longitude: -122.7)
        let existing = makeSummary(generatedAt: referenceDate)

        XCTAssertTrue(ThreeNightOutlookPersistencePolicy.shouldSave(
            decision: .publish(existing),
            existing: existing,
            targetLocation: targetLocation,
            referenceDate: referenceDate
        ))
    }

    func testDashboardMaySaveUnavailableSummaryForWrongLocationOrMalformedExistingSummary() {
        let referenceDate = date(day: 25, hour: 20)
        let targetLocation = CachedLocation(name: "Home", latitude: 45.5, longitude: -122.7)
        let unavailable = ThreeNightOutlookWidgetPayloadBuilder.makeUnavailableSummary(
            generatedAt: referenceDate,
            location: targetLocation,
            timeZone: timeZone,
            referenceDate: referenceDate
        )
        let wrongLocation = makeSummary(generatedAt: referenceDate, latitude: 47.6)
        var malformedNights = makeNights()
        malformedNights.swapAt(0, 1)
        let malformed = makeSummary(generatedAt: referenceDate, nights: malformedNights)

        XCTAssertTrue(ThreeNightOutlookPersistencePolicy.shouldSave(
            decision: .unavailable(unavailable),
            existing: wrongLocation,
            targetLocation: targetLocation,
            referenceDate: referenceDate
        ))
        XCTAssertTrue(ThreeNightOutlookPersistencePolicy.shouldSaveUnavailable(
            existing: malformed,
            targetLocation: targetLocation,
            referenceDate: referenceDate
        ))
    }

    func testDashboardMaySaveUnavailableSummaryWithoutDataBearingExistingSummary() {
        let referenceDate = date(day: 25, hour: 20)
        let targetLocation = CachedLocation(name: "Home", latitude: 45.5, longitude: -122.7)
        let unavailable = ThreeNightOutlookWidgetPayloadBuilder.makeUnavailableSummary(
            generatedAt: referenceDate,
            location: targetLocation,
            timeZone: timeZone,
            referenceDate: referenceDate
        )
        let nonDataBearing = makeSummary(nights: makeNights().map { night in
            self.night(
                label: night.displayLabel,
                day: calendar.component(.day, from: night.observingDate),
                score: nil,
                status: .unavailable,
                isBest: false
            )
        })

        XCTAssertTrue(ThreeNightOutlookPersistencePolicy.shouldSave(
            decision: .unavailable(unavailable),
            existing: nil,
            targetLocation: targetLocation,
            referenceDate: referenceDate
        ))
        XCTAssertTrue(ThreeNightOutlookPersistencePolicy.shouldSaveUnavailable(
            existing: nonDataBearing,
            targetLocation: targetLocation,
            referenceDate: referenceDate
        ))
    }

    func testDashboardBlocksNonDataBearingPublicationOnlyForUsefulRecentSummary() {
        let referenceDate = date(day: 25, hour: 20)
        let targetLocation = CachedLocation(name: "Home", latitude: 45.5, longitude: -122.7)
        let existing = makeSummary(generatedAt: referenceDate)
        let nonDataBearing = ThreeNightOutlookWidgetPayloadBuilder.makeUnavailableSummary(
            generatedAt: referenceDate,
            location: targetLocation,
            timeZone: timeZone,
            referenceDate: referenceDate
        )

        XCTAssertFalse(ThreeNightOutlookPersistencePolicy.shouldSave(
            decision: .publish(nonDataBearing),
            existing: existing,
            targetLocation: targetLocation,
            referenceDate: referenceDate
        ))
        for invalidExisting in [
            makeSummary(generatedAt: date(day: 24, hour: 19)),
            makeSummary(generatedAt: referenceDate, latitude: 47.6),
            makeSummary(generatedAt: referenceDate, nights: Array(existing.nights.prefix(2))),
            nonDataBearing,
            nil
        ] as [WidgetThreeNightOutlookSummary?] {
            XCTAssertTrue(ThreeNightOutlookPersistencePolicy.shouldSave(
                decision: .publish(nonDataBearing),
                existing: invalidExisting,
                targetLocation: targetLocation,
                referenceDate: referenceDate
            ))
        }
    }

    func testFailedRefreshUsesMatchingActiveSummaryThroughTwentyFourHours() {
        let referenceDate = date(day: 26, hour: 1)
        let cachedSummary = makeSummary(
            generatedAt: date(day: 25, hour: 20),
            nights: shiftedNights(startDay: 25)
        )
        let entry = ThreeNightOutlookEntryResolver.failedRefreshEntry(
            cachedSummary: cachedSummary,
            selectedLocation: selectedLocation(),
            referenceDate: referenceDate
        )

        guard case let .available(summary) = entry.state else {
            return XCTFail("Expected bounded last-known-good fallback")
        }
        XCTAssertEqual(summary, cachedSummary)
        XCTAssertEqual(entry.dataStatus?.provenance, .fallback)
        XCTAssertEqual(entry.dataStatus?.dataAsOf, cachedSummary.generatedAt)
    }

    func testFailedRefreshRejectsSummaryOlderThanTwentyFourHours() {
        let entry = ThreeNightOutlookEntryResolver.failedRefreshEntry(
            cachedSummary: makeSummary(
                generatedAt: date(day: 24, hour: 0),
                nights: shiftedNights(startDay: 25)
            ),
            selectedLocation: selectedLocation(),
            referenceDate: date(day: 26, hour: 1)
        )
        guard case .unavailable = entry.state else {
            return XCTFail("Expected fallback older than 24 hours to be rejected")
        }
    }

    func testFailedRefreshRejectsWrongLocationSummary() {
        let entry = ThreeNightOutlookEntryResolver.failedRefreshEntry(
            cachedSummary: makeSummary(
                generatedAt: date(day: 25, hour: 20),
                latitude: 47.6,
                nights: shiftedNights(startDay: 25)
            ),
            selectedLocation: selectedLocation(),
            referenceDate: date(day: 26, hour: 1)
        )
        guard case .unavailable = entry.state else {
            return XCTFail("Expected wrong-location fallback to be rejected")
        }
    }

    func testFailedRefreshRejectsObservingNightMismatch() {
        let entry = ThreeNightOutlookEntryResolver.failedRefreshEntry(
            cachedSummary: makeSummary(
                generatedAt: date(day: 25, hour: 20),
                nights: shiftedNights(startDay: 24)
            ),
            selectedLocation: selectedLocation(),
            referenceDate: date(day: 26, hour: 1)
        )
        guard case .unavailable = entry.state else {
            return XCTFail("Expected wrong-night fallback to be rejected")
        }
    }

    func testFailedRefreshRejectsNonDataBearingSummary() {
        let nights = shiftedNights(startDay: 25).map { night in
            self.night(
                label: night.displayLabel,
                day: calendar.component(.day, from: night.observingDate),
                score: nil,
                status: .available,
                isBest: false
            )
        }
        let entry = ThreeNightOutlookEntryResolver.failedRefreshEntry(
            cachedSummary: makeSummary(generatedAt: date(day: 25, hour: 20), nights: nights),
            selectedLocation: selectedLocation(),
            referenceDate: date(day: 26, hour: 1)
        )
        guard case .unavailable = entry.state else {
            return XCTFail("Expected non-data-bearing fallback to be rejected")
        }
    }

    func testPublicationBeforeMidnightStartsWithCurrentObservingDate() {
        let referenceDate = date(day: 25, hour: 20)
        let savedLocationID = UUID()
        let decision = ThreeNightOutlookWidgetPayloadBuilder.publicationDecision(
            conditions: makeConditions(referenceDate: referenceDate, locationID: savedLocationID),
            existingSummary: nil, referenceDate: referenceDate, timeZone: timeZone
        )
        guard case let .publish(summary) = decision else {
            return XCTFail("Expected a published outlook")
        }
        XCTAssertEqual(summary.nights.map(\.observingDate), [date(day: 25), date(day: 26), date(day: 27)])
        XCTAssertEqual(summary.nights.map(\.displayLabel), ["Tonight", "Tomorrow", "Day After"])
        XCTAssertEqual(summary.savedLocationID, savedLocationID)
    }

    func testPublicationDuringReconstructableActiveNightKeepsPreviousDate() {
        let referenceDate = date(day: 26, hour: 1)
        let decision = ThreeNightOutlookWidgetPayloadBuilder.publicationDecision(
            conditions: makeConditions(referenceDate: referenceDate, dataStartDay: 25),
            existingSummary: nil, referenceDate: referenceDate, timeZone: timeZone
        )
        guard case let .publish(summary) = decision else {
            return XCTFail("Expected the reconstructable active night")
        }
        XCTAssertEqual(summary.nights.first?.observingDate, date(day: 25))
    }

    func testPublicationAfterActiveNightEndsUsesUpcomingCurrentDate() {
        let referenceDate = date(day: 26, hour: 4).addingTimeInterval(1)
        let decision = ThreeNightOutlookWidgetPayloadBuilder.publicationDecision(
            conditions: makeConditions(referenceDate: referenceDate, dataStartDay: 26),
            existingSummary: nil, referenceDate: referenceDate, timeZone: timeZone
        )
        guard case let .publish(summary) = decision else {
            return XCTFail("Expected the upcoming evening")
        }
        XCTAssertEqual(summary.nights.first?.observingDate, date(day: 26))
    }

    func testFreshPostMidnightPublicationPreservesOnlyValidExistingPayload() {
        let referenceDate = date(day: 26, hour: 1)
        let conditions = makeConditions(referenceDate: referenceDate, dataStartDay: 26)
        let valid = makeSummary(
            generatedAt: referenceDate,
            nights: shiftedNights(startDay: 25)
        )
        assertPreserved(conditions: conditions, existing: valid, referenceDate: referenceDate)

        assertUnavailable(conditions: conditions, existing: nil, referenceDate: referenceDate)
        assertUnavailable(
            conditions: conditions,
            existing: makeSummary(
                generatedAt: date(day: 25, hour: 21).addingTimeInterval(-1),
                nights: shiftedNights(startDay: 25)
            ),
            referenceDate: referenceDate
        )
        assertUnavailable(
            conditions: conditions,
            existing: makeSummary(
                generatedAt: date(day: 25, hour: 23), latitude: 47.6,
                nights: shiftedNights(startDay: 25)
            ),
            referenceDate: referenceDate
        )
        assertUnavailable(
            conditions: conditions,
            existing: makeSummary(
                generatedAt: date(day: 25, hour: 23), nights: shiftedNights(startDay: 24)
            ),
            referenceDate: referenceDate
        )
        assertUnavailable(
            conditions: conditions,
            existing: makeSummary(
                generatedAt: date(day: 25, hour: 23),
                nights: Array(shiftedNights(startDay: 25).prefix(2))
            ),
            referenceDate: referenceDate
        )
        let ordered = shiftedNights(startDay: 25)
        assertUnavailable(
            conditions: conditions,
            existing: makeSummary(
                generatedAt: date(day: 25, hour: 23),
                nights: [ordered[0], ordered[2], ordered[1]]
            ),
            referenceDate: referenceDate
        )
        assertUnavailable(
            conditions: conditions,
            existing: makeSummary(
                generatedAt: date(day: 25, hour: 23), status: .unavailable,
                nights: shiftedNights(startDay: 25)
            ),
            referenceDate: referenceDate
        )
    }

    func testInsufficientDailyDataPublishesUnavailableWithoutIndexingPastEnd() {
        let referenceDate = date(day: 25, hour: 20)
        let decision = ThreeNightOutlookWidgetPayloadBuilder.publicationDecision(
            conditions: makeConditions(
                referenceDate: referenceDate, dailyCount: 2
            ),
            existingSummary: nil, referenceDate: referenceDate, timeZone: timeZone
        )
        guard case .unavailable = decision else {
            return XCTFail("Expected unavailable for a partial three-night forecast")
        }
    }

    func testNoBestNightWhenEveryRowIsUnavailable() {
        let summary = makeSummary(nights: makeNights().map {
            night(
                label: $0.displayLabel, day: calendar.component(.day, from: $0.observingDate),
                score: nil, status: .unavailable, isBest: false
            )
        })
        XCTAssertFalse(summary.nights.contains(where: \.isBestNight))
        XCTAssertNil(ThreeNightOutlookWidgetPayloadBuilder.bestNightIndex(in: summary.nights))
    }

    func testHighestScoreWinsWithoutChangingOrder() {
        let nights = [
            night(label: "Tonight", day: 25, score: 72, status: .available, isBest: false),
            night(label: "Tomorrow", day: 26, score: 91, status: .available, isBest: false),
            night(label: "Day After", day: 27, score: 80, status: .available, isBest: false)
        ]
        XCTAssertEqual(ThreeNightOutlookWidgetPayloadBuilder.bestNightIndex(in: nights), 1)
        XCTAssertEqual(nights.map(\.displayLabel), ["Tonight", "Tomorrow", "Day After"])
    }

    func testBestNightTieSelectsEarliest() {
        let nights = [
            night(label: "Tonight", day: 25, score: 91, status: .available, isBest: false),
            night(label: "Tomorrow", day: 26, score: 91, status: .available, isBest: false),
            night(label: "Day After", day: 27, score: 80, status: .available, isBest: false)
        ]
        XCTAssertEqual(ThreeNightOutlookWidgetPayloadBuilder.bestNightIndex(in: nights), 0)
    }

    func testPresentationUsesExplicitMissingWindowStatus() {
        let row = WidgetThreeNightOutlookNight(
            id: "Tonight", displayLabel: "Tonight", observingDate: date(day: 25),
            score: 75, verdict: "Good", scoreTone: .informational,
            astronomicalNightStart: date(day: 25, hour: 22),
            astronomicalNightEnd: date(day: 26, hour: 4), bestWindow: nil,
            statusText: "No best window available", status: .available, isBestNight: true
        )
        XCTAssertEqual(
            WidgetThreeNightOutlookPresentation.windowText(
                for: row, timeZone: timeZone, compact: false
            ),
            "No best window available"
        )
        XCTAssertEqual(
            WidgetThreeNightOutlookPresentation.windowText(
                for: row, timeZone: timeZone, compact: true
            ),
            "No best window available"
        )
    }

    func testRegularAndCompactMinimalBestWindowWording() {
        let row = night(
            label: "Tonight", day: 25, score: 75,
            status: .available, isBest: true
        )
        let range = DateFormatters.formatTimeRange(
            from: date(day: 25, hour: 23),
            to: date(day: 26, hour: 1),
            in: timeZone
        ).replacingOccurrences(of: " ", with: "\u{00A0}")

        XCTAssertEqual(
            WidgetThreeNightOutlookPresentation.windowText(
                for: row, timeZone: timeZone, compact: false
            ),
            "Best window \(range)"
        )
        let compactAndMinimal = WidgetThreeNightOutlookPresentation.windowText(
            for: row, timeZone: timeZone, compact: true
        )
        XCTAssertEqual(compactAndMinimal, "Best \(range)")
        XCTAssertTrue(compactAndMinimal.contains("PM"))
        XCTAssertTrue(compactAndMinimal.contains("AM"))
        XCTAssertFalse(compactAndMinimal.contains("11:00 PM"))
        XCTAssertFalse(compactAndMinimal.contains("1:00 AM"))
    }

    func testTimelineAndExtensionArchitectureSourceConstraints() throws {
        let provider = try source("Sources/Widgets/ThreeNightOutlookTimelineProvider.swift")
        let resolver = try source("Sources/Widgets/ThreeNightOutlookEntryResolver.swift")
        XCTAssertTrue(provider.contains("timelineReevaluationInterval: TimeInterval = 3600"))
        let widgetSources = try [
            "Sources/Widgets/ThreeNightOutlookTimelineProvider.swift",
            "Sources/Widgets/ThreeNightOutlookEntryResolver.swift",
            "Sources/Widgets/ThreeNightOutlookWidgetMediumEntryView.swift",
            "Sources/Widgets/WidgetThreeNightOutlookPresentation.swift"
        ].map(source).joined()
        for forbidden in [
            "NightQualityAnalyzer", "TargetRecommendationService", "widgetURL",
            "Link(", ".system(size:", ".minimumScaleFactor", ".lineLimit(",
            ".dynamicTypeSize(", ".truncationMode("
        ] {
            XCTAssertFalse(widgetSources.contains(forbidden), forbidden)
        }
        XCTAssertTrue(provider.contains("let repository = SharedConditionsRepository()"))
        XCTAssertTrue(provider.contains("repository.conditions("))
        XCTAssertTrue(provider.contains("repository.matchingCachedConditions"))
        XCTAssertTrue(provider.contains("saveWidgetThreeNightOutlookSummaryAsync"))
        XCTAssertTrue(provider.contains("ThreeNightOutlookEntryResolver.buildEntry"))
        XCTAssertTrue(resolver.contains("ThreeNightOutlookWidgetPayloadBuilder.publicationDecision"))
        XCTAssertTrue(resolver.contains("retainedConditions"))
        XCTAssertTrue(resolver.contains("failedRefreshEntry"))
        XCTAssertTrue(provider.contains("context.isPreview"))
        XCTAssertTrue(provider.contains("Timeline invocation"))
        XCTAssertFalse(provider.contains("payloadMaximumAge"))
    }

    func testVisibleWidgetTerminologyUsesForecast() throws {
        let entry = try source("Sources/Widgets/ThreeNightOutlookEntry.swift")
        let widget = try source("Sources/Widgets/ThreeNightOutlookWidget.swift")
        let view = try source("Sources/Widgets/ThreeNightOutlookWidgetMediumEntryView.swift")
        let presentation = try source("Sources/Widgets/WidgetThreeNightOutlookPresentation.swift")
        let visibleSources = [entry, widget, view].joined(separator: "\n")
        XCTAssertTrue(visibleSources.contains("Three-Night Forecast"))
        XCTAssertTrue(visibleSources.contains("Forecast unavailable"))
        XCTAssertTrue(visibleSources.contains("Forecast is for another location"))
        XCTAssertTrue(view.contains("night.verdict == \"N/A\" ? \"N/A\" : \"—\""))
        XCTAssertTrue(view.contains("if showsVerdict, night.verdict != \"N/A\""))
        XCTAssertTrue(presentation.contains("return night.statusText"))
        XCTAssertFalse(visibleSources.contains("Outlook needs an update"))
        XCTAssertFalse(visibleSources.contains("Three-Night Outlook"))
    }

    func testReleaseUnavailableUIUsesNormalMessageWithoutFieldDiagnostics() throws {
        let entry = try source("Sources/Widgets/ThreeNightOutlookEntry.swift")
        let widget = try source("Sources/Widgets/ThreeNightOutlookWidget.swift")
        let visibleSources = [entry, widget].joined(separator: "\n")

        XCTAssertTrue(visibleSources.contains("Open Astro Conditions to update"))
        for diagnosticText in [
            "ThreeNightOutlookDiagnostic",
            "PRESENTATION-AGE",
            "FALLBACK-AGE",
            "ENTRY-",
            "Diag "
        ] {
            XCTAssertFalse(visibleSources.contains(diagnosticText), diagnosticText)
        }
    }

    func testIncompleteRowUsesOneNAAndOneNeedsFreshDataLineAcrossLayoutModes() throws {
        let row = WidgetThreeNightOutlookNight(
            id: "Day After", displayLabel: "Day After", observingDate: date(day: 28),
            score: nil, verdict: "N/A", scoreTone: nil,
            astronomicalNightStart: date(day: 28, hour: 22),
            astronomicalNightEnd: date(day: 29, hour: 4), bestWindow: nil,
            statusText: "Needs fresh data", status: .unavailable, isBestNight: false
        )
        XCTAssertEqual(
            WidgetThreeNightOutlookPresentation.windowText(
                for: row, timeZone: timeZone, compact: false
            ),
            "Needs fresh data"
        )
        XCTAssertEqual(
            WidgetThreeNightOutlookPresentation.windowText(
                for: row, timeZone: timeZone, compact: true
            ),
            "Needs fresh data"
        )

        let view = try source("Sources/Widgets/ThreeNightOutlookWidgetMediumEntryView.swift")
        XCTAssertTrue(view.contains("private func standardCandidates()"))
        XCTAssertTrue(view.contains("private func largestStandardCandidates()"))
        XCTAssertTrue(view.contains("private func accessibilityCandidates()"))
        XCTAssertTrue(view.contains("if showsVerdict, night.verdict != \"N/A\""))
    }

    func testEveryLayoutCandidateRetainsThreeRowLoopAndSharedIdentity() throws {
        let view = try source("Sources/Widgets/ThreeNightOutlookWidgetMediumEntryView.swift")
        let candidates = contentCandidateArguments(in: view).filter {
            $0.contains("showsSymbol: true") || $0.contains("showsSymbol: false")
        }
        XCTAssertEqual(candidates.count, 7)
        XCTAssertTrue(candidates.allSatisfy { $0.contains("showsSymbol: true") })
        XCTAssertFalse(candidates.contains { $0.contains("showsSymbol: false") })
        XCTAssertEqual(
            view.components(separatedBy: "ForEach(Array(summary.nights.enumerated())").count - 1,
            1
        )
        XCTAssertTrue(view.contains("Image(systemName: WidgetAppIdentity.symbol)"))
        XCTAssertNotEqual(WidgetAppIdentity.symbol, "calendar")
    }

    func testAllHomeScreenWidgetsUseSharedIdentityIncludingUnavailableState() throws {
        let phaseOneSources = try [
            "Sources/Widgets/NightConditionsWidget.swift",
            "Sources/Widgets/NightConditionsWidgetMediumEntryView.swift",
            "Sources/Widgets/NightConditionsWidgetSmallEntryView.swift"
        ].map(source)
        let phaseTwoSources = try [
            "Sources/Widgets/TonightTargetsWidget.swift",
            "Sources/Widgets/TonightTargetsWidgetMediumEntryView.swift"
        ].map(source)
        let phaseThreeView = try source(
            "Sources/Widgets/ThreeNightOutlookWidgetMediumEntryView.swift"
        )
        let phaseThreeWidget = try source(
            "Sources/Widgets/ThreeNightOutlookWidget.swift"
        )

        for widgetSource in phaseOneSources + phaseTwoSources
            + [phaseThreeView, phaseThreeWidget] {
            XCTAssertTrue(widgetSource.contains("WidgetAppIdentity.symbol"))
        }
        XCTAssertTrue(phaseThreeWidget.contains(
            "systemImage: WidgetAppIdentity.symbol"
        ))

        let phaseThreeIdentitySources = try [
            "Sources/Widgets/ThreeNightOutlookWidgetMediumEntryView.swift",
            "Sources/Widgets/ThreeNightOutlookWidget.swift",
            "Sources/Widgets/WidgetThreeNightOutlookPresentation.swift"
        ].map(source).joined(separator: "\n")
        XCTAssertFalse(phaseThreeIdentitySources.contains("\"calendar\""))
    }

    func testLayoutModeByDynamicTypeSize() {
        for size in [
            DynamicTypeSize.xSmall, .small, .medium, .large, .xLarge, .xxLarge
        ] {
            XCTAssertEqual(
                ThreeNightOutlookLayoutPolicy.mode(for: size),
                .standardWithLocationPreference,
                "\(size) should use the standard location hierarchy"
            )
        }
        XCTAssertEqual(
            ThreeNightOutlookLayoutPolicy.mode(for: .xxxLarge),
            .largestStandard
        )
        for size in [
            DynamicTypeSize.accessibility1, .accessibility2, .accessibility3,
            .accessibility4, .accessibility5
        ] {
            XCTAssertEqual(
                ThreeNightOutlookLayoutPolicy.mode(for: size),
                .accessibility,
                "\(size) should use the accessibility hierarchy"
            )
        }
    }

    func testStandardCandidateOrderIncludesCompactLocationFallback() throws {
        let view = try source("Sources/Widgets/ThreeNightOutlookWidgetMediumEntryView.swift")
        let section = try sourceSection(
            in: view,
            from: "private func standardCandidates()",
            through: "private func largestStandardCandidates()"
        )
        XCTAssertEqual(
            normalizedCandidates(in: section),
            [
                "style: .regular, showsLocation: true, showsVerdict: true, showsSymbol: true",
                "style: .compact, showsLocation: true, showsVerdict: true, showsSymbol: true",
                "style: .compact, showsLocation: false, showsVerdict: true, showsSymbol: true",
                "style: .minimal, showsLocation: false, showsVerdict: false, showsSymbol: true"
            ]
        )
    }

    func testLargestStandardCandidateOrderStartsCompactWithoutOptionalText() throws {
        let view = try source("Sources/Widgets/ThreeNightOutlookWidgetMediumEntryView.swift")
        let section = try sourceSection(
            in: view,
            from: "private func largestStandardCandidates()",
            through: "private func accessibilityCandidates()"
        )
        XCTAssertEqual(
            normalizedCandidates(in: section),
            [
                "style: .compact, showsLocation: false, showsVerdict: false, showsSymbol: true",
                "style: .minimal, showsLocation: false, showsVerdict: false, showsSymbol: true"
            ]
        )
    }

    func testAccessibilityCandidatesOmitLocationAndVerdicts() throws {
        let view = try source("Sources/Widgets/ThreeNightOutlookWidgetMediumEntryView.swift")
        let section = try sourceSection(
            in: view,
            from: "private func accessibilityCandidates()",
            through: "private func content"
        )
        let candidates = normalizedCandidates(in: section)
        XCTAssertEqual(candidates, [
            "style: .minimal, showsLocation: false, showsVerdict: false, showsSymbol: true"
        ])
    }

    func testPhaseThreeViewKeepsForbiddenLayoutTechniquesOut() throws {
        let view = try source(
            "Sources/Widgets/ThreeNightOutlookWidgetMediumEntryView.swift"
        )
        for forbidden in [
            ".system(size:", ".lineLimit(", ".minimumScaleFactor",
            ".truncationMode(", ".dynamicTypeSize(", "GeometryReader",
            ".clipped(", ".clipShape(", "padding(-"
        ] {
            XCTAssertFalse(view.contains(forbidden), forbidden)
        }
        XCTAssertTrue(view.contains("showsLocation: true"))
        XCTAssertTrue(view.contains("showsLocation: false"))
    }

    func testReloadServiceIncludesAllHomeScreenWidgetKinds() throws {
        let source = try source("Sources/SharedCode/Core/Services/WidgetReloadService.swift")
        for kind in ["NightConditionsWidget", "TonightTargetsWidget", "ThreeNightOutlookWidget"] {
            XCTAssertTrue(source.contains(kind))
        }
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func date(day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 7, day: day, hour: hour, minute: minute
        ))!
    }

    private func unavailablePublicationEntry(
        cachedSummary: WidgetThreeNightOutlookSummary,
        referenceDate: Date
    ) async -> ThreeNightOutlookEntry {
        let location = selectedLocation()
        return await ThreeNightOutlookEntryResolver.buildEntry(
            location: location,
            cachedSummary: cachedSummary,
            cachedLocation: CachedLocation(
                name: location.name,
                latitude: location.latitude,
                longitude: location.longitude
            ),
            referenceDate: referenceDate,
            normalConditions: {
                makeConditions(
                    referenceDate: referenceDate,
                    dataStartDay: 25,
                    dailyCount: 2
                )
            },
            retainedConditions: { nil },
            save: { _ in }
        )
    }

    private func night(
        label: String, day: Int, score: Int?, status: WidgetThreeNightOutlookNightStatus,
        isBest: Bool, bestWindow: NightQualityAssessment.TimeWindow? = nil,
        statusText: String = "Best window"
    ) -> WidgetThreeNightOutlookNight {
        WidgetThreeNightOutlookNight(
            id: label, displayLabel: label, observingDate: date(day: day),
            score: score, verdict: score == nil ? "Unavailable" : "Good",
            scoreTone: score == nil ? nil : .informational,
            astronomicalNightStart: date(day: day, hour: 22),
            astronomicalNightEnd: date(day: day + 1, hour: 4),
            bestWindow: bestWindow ?? (score == nil ? nil : .init(
                start: date(day: day, hour: 23), end: date(day: day + 1, hour: 1)
            )),
            statusText: statusText, status: status, isBestNight: isBest
        )
    }

    private func makeNights() -> [WidgetThreeNightOutlookNight] {
        [
            night(label: "Tonight", day: 25, score: 87, status: .available, isBest: true),
            night(label: "Tomorrow", day: 26, score: 72, status: .available, isBest: false),
            night(label: "Day After", day: 27, score: 48, status: .available, isBest: false)
        ]
    }

    private func shiftedNights(startDay: Int) -> [WidgetThreeNightOutlookNight] {
        [
            night(label: "Tonight", day: startDay, score: 87, status: .available, isBest: true),
            night(label: "Tomorrow", day: startDay + 1, score: 72, status: .available, isBest: false),
            night(label: "Day After", day: startDay + 2, score: 48, status: .available, isBest: false)
        ]
    }

    private func makeSummary(
        generatedAt: Date? = nil, locationName: String = "Home",
        latitude: Double = 45.5,
        savedLocationID: UUID? = nil,
        status: WidgetThreeNightOutlookStatus = .available,
        nights: [WidgetThreeNightOutlookNight]? = nil
    ) -> WidgetThreeNightOutlookSummary {
        WidgetThreeNightOutlookSummary(
            generatedAt: generatedAt ?? date(day: 25, hour: 20),
            locationName: locationName, latitude: latitude, longitude: -122.7,
            savedLocationID: savedLocationID,
            timeZoneIdentifier: timeZone.identifier, status: status,
            nights: nights ?? makeNights()
        )
    }

    private func makeConditions(
        referenceDate: Date,
        fetchedAt: Date? = nil,
        dataStartDay: Int = 25,
        dailyCount: Int = 4,
        locationID: UUID? = nil
    ) -> ViewingConditions {
        let start = date(day: dataStartDay)
        let forecasts = (0..<(4 * 24)).map { offset in
            return HourlyForecast(
                time: start.addingTimeInterval(TimeInterval(offset) * 3600),
                cloudCover: 20 + offset % 10, humidity: 45, windSpeed: 2,
                windDirection: 180, temperature: 12, dewPoint: 5, visibility: 20_000
            )
        }
        let sunEvents = (0..<dailyCount).map { offset in
            let day = dataStartDay + offset
            return SunEvents(
                sunrise: date(day: day, hour: 6), sunset: date(day: day, hour: 20),
                civilTwilightBegin: date(day: day, hour: 5),
                civilTwilightEnd: date(day: day, hour: 21),
                nauticalTwilightBegin: date(day: day, hour: 4),
                nauticalTwilightEnd: date(day: day, hour: 21),
                astronomicalTwilightBegin: date(day: day, hour: 4),
                astronomicalTwilightEnd: date(day: day, hour: 22)
            )
        }
        return ViewingConditions(
            fetchedAt: fetchedAt ?? referenceDate,
            location: CachedLocation(
                id: locationID, name: "Home", latitude: 45.5, longitude: -122.7
            ),
            hourlyForecasts: forecasts, dailySunEvents: sunEvents,
            dailyMoonInfo: (0..<dailyCount).map {
                MoonInfo(
                    phase: 0.2, phaseName: "Waxing", altitude: 10,
                    illumination: 20 + $0, emoji: "🌒"
                )
            },
            issPasses: [], fogScore: FogScore(score: 0, factors: []),
            timeZoneIdentifier: timeZone.identifier
        )
    }

    /// Uses four calendar days of hourly data, plus July 29 solar ephemeris
    /// solely to express the final July 28 astronomical-night boundary.
    private func makeFourCalendarDayHourlyConditions(
        referenceDate: Date,
        fetchedAt: Date? = nil,
        hourlyDayCount: Int = 4,
        missingHours: Set<Date> = [],
        location: CachedLocation = CachedLocation(name: "Home", latitude: 45.5, longitude: -122.7)
    ) -> ViewingConditions {
        let forecasts = (0..<(hourlyDayCount * 24)).compactMap { offset -> HourlyForecast? in
            let time = date(day: 25).addingTimeInterval(TimeInterval(offset) * 3600)
            guard !missingHours.contains(time) else { return nil }
            return HourlyForecast(
                time: time,
                cloudCover: 20, humidity: 45, windSpeed: 2,
                windDirection: 180, temperature: 12, dewPoint: 5, visibility: 20_000
            )
        }
        let sunEvents = (25...29).map { day in
            SunEvents(
                sunrise: date(day: day, hour: 6), sunset: date(day: day, hour: 20),
                civilTwilightBegin: date(day: day, hour: 5),
                civilTwilightEnd: date(day: day, hour: 21),
                nauticalTwilightBegin: date(day: day, hour: 4),
                nauticalTwilightEnd: date(day: day, hour: 21),
                astronomicalTwilightBegin: date(day: day, hour: 4, minute: 37),
                astronomicalTwilightEnd: date(day: day, hour: 22, minute: 18)
            )
        }
        return ViewingConditions(
            fetchedAt: fetchedAt ?? referenceDate,
            location: location,
            hourlyForecasts: forecasts,
            dailySunEvents: sunEvents,
            dailyMoonInfo: (0..<sunEvents.count).map { offset in
                MoonInfo(
                    phase: 0.2, phaseName: "Waxing", altitude: 10,
                    illumination: 20 + offset, emoji: "🌒"
                )
            },
            issPasses: [], fogScore: FogScore(score: 0, factors: []),
            timeZoneIdentifier: timeZone.identifier
        )
    }

    private func hourlyCoverage(
        for resolution: TargetRecommendationContextResolution
    ) -> HourlyCoverage {
        let start = resolution.context.astronomicalNightStart
        let end = resolution.context.astronomicalNightEnd
        let forecasts = resolution.context.nightQuality.hourlyRatings
        let first = forecasts.first?.time
        let last = forecasts.last?.time
        return HourlyCoverage(
            observingDate: resolution.observingDate,
            astronomicalNightStart: start,
            astronomicalNightEnd: end,
            firstRelevantHourlyTimestamp: first,
            lastRelevantHourlyTimestamp: last,
            reachesAstronomicalNightEnd: last.map {
                $0.addingTimeInterval(60 * 60) >= end
            } ?? false
        )
    }

    private func resolve(
        _ summary: WidgetThreeNightOutlookSummary?,
        _ location: SelectedLocation?,
        at date: Date
    ) -> ThreeNightOutlookResolvedState {
        ThreeNightOutlookEntryResolver.resolve(
            summary: summary, selectedLocation: location, referenceDate: date
        )
    }

    private func selectedLocation(
        id: UUID? = nil,
        latitude: Double = 45.5,
        longitude: Double = -122.7,
        source: SelectedLocation.Source = .currentGPS
    ) -> SelectedLocation {
        SelectedLocation(
            source: source,
            id: id,
            name: "Home",
            latitude: latitude,
            longitude: longitude
        )
    }

    private func assertPreserved(
        conditions: ViewingConditions,
        existing: WidgetThreeNightOutlookSummary?,
        referenceDate: Date,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let decision = ThreeNightOutlookWidgetPayloadBuilder.publicationDecision(
            conditions: conditions, existingSummary: existing,
            referenceDate: referenceDate, timeZone: timeZone
        )
        guard case .preserveExisting = decision else {
            return XCTFail("Expected preserveExisting", file: file, line: line)
        }
    }

    private func assertUnavailable(
        conditions: ViewingConditions,
        existing: WidgetThreeNightOutlookSummary?,
        referenceDate: Date,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let decision = ThreeNightOutlookWidgetPayloadBuilder.publicationDecision(
            conditions: conditions, existingSummary: existing,
            referenceDate: referenceDate, timeZone: timeZone
        )
        guard case .unavailable = decision else {
            return XCTFail("Expected unavailable", file: file, line: line)
        }
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func sourceSection(
        in source: String, from startMarker: String, through endMarker: String
    ) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMarker)?.lowerBound)
        let end = try XCTUnwrap(
            source.range(of: endMarker, range: start..<source.endIndex)?.upperBound
        )
        return String(source[start..<end])
    }

    private func contentCandidateArguments(in source: String) -> [String] {
        let marker = "content("
        var values: [String] = []
        var start = source.startIndex
        while let markerRange = source.range(of: marker, range: start..<source.endIndex),
              let end = source.range(of: ")", range: markerRange.upperBound..<source.endIndex) {
            values.append(String(source[markerRange.upperBound..<end.lowerBound]))
            start = end.upperBound
        }
        return values
    }

    private func normalizedCandidates(in source: String) -> [String] {
        contentCandidateArguments(in: source).map {
            $0.components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
    }
}

private struct HourlyCoverage: Equatable {
    let observingDate: Date
    let astronomicalNightStart: Date
    let astronomicalNightEnd: Date
    let firstRelevantHourlyTimestamp: Date?
    let lastRelevantHourlyTimestamp: Date?
    let reachesAstronomicalNightEnd: Bool
}

private enum DayRolloverRefreshError: Error, Equatable {
    case failed
}

private actor FetchAttemptRecorder {
    private var count = 0

    func record() {
        count += 1
    }

    func total() -> Int { count }
}

private actor SummaryRecorder {
    private var summaries: [WidgetThreeNightOutlookSummary] = []

    func record(_ summary: WidgetThreeNightOutlookSummary) {
        summaries.append(summary)
    }

    func values() -> [WidgetThreeNightOutlookSummary] { summaries }
}

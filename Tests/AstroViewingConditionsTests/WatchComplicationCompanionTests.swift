import Foundation
import XCTest
@testable import SharedCode

final class WatchComplicationCompanionDisplayPolicyTests: XCTestCase {
    private let latitude = Phase4BFixtures.latitude
    private let longitude = Phase4BFixtures.longitude
    private let timeZoneID = Phase4BFixtures.timeZoneID

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timeZoneID)!
        return cal
    }

    // MARK: - Basic gates

    func testMissingSelectedLocationIsUnavailable() {
        let conditions = Phase4BFixtures.analyzableConditions(locationID: UUID())
        let result = WatchComplicationCompanionDisplayPolicy.evaluate(
            selectedLocation: nil,
            conditions: conditions
        )
        guard case .failure(.noSelectedLocation) = result else {
            return XCTFail("expected noSelectedLocation, got \(result)")
        }
    }

    func testMissingConditionsIsUnavailable() {
        let result = WatchComplicationCompanionDisplayPolicy.evaluate(
            selectedLocation: selectedLocation(id: UUID()),
            conditions: nil
        )
        guard case .failure(.noConditions) = result else {
            return XCTFail("expected noConditions, got \(result)")
        }
    }

    func testLocationMismatchIsUnavailable() {
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(
            locationID: id,
            lat: latitude + 1.0
        )
        let result = WatchComplicationCompanionDisplayPolicy.evaluate(
            selectedLocation: selectedLocation(id: id),
            conditions: conditions
        )
        guard case .failure(.locationMismatch) = result else {
            return XCTFail("expected locationMismatch, got \(result)")
        }
    }

    func testStaleBeyondCompanionMaxAgeIsUnavailable() {
        let id = UUID()
        // Anchor conditions around a fixed evening, then advance reference past 24h.
        let evening = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026, month: 6, day: 1, hour: 21
        ))!
        let conditions = Phase4BFixtures.analyzableConditions(
            locationID: id,
            referenceDate: evening
        )
        let reference = evening.addingTimeInterval(
            WatchComplicationCompanionDisplayPolicy.companionDisplayMaxAge + 60
        )
        let result = WatchComplicationCompanionDisplayPolicy.evaluate(
            selectedLocation: selectedLocation(id: id),
            conditions: conditions,
            referenceDate: reference
        )
        guard case .failure(.stale) = result else {
            return XCTFail("expected stale, got \(result)")
        }
    }

    // MARK: - Active observing night (cross-midnight)

    /// Evening pair must remain displayable after local midnight while still inside
    /// the same astronomical night (ActiveObservingNightResolver dayOffset -1 window).
    func testEveningPairRemainsDisplayableAfterMidnightDuringActiveAstronomicalNight() {
        let id = UUID()
        let evening = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026, month: 6, day: 1, hour: 21
        ))!
        // Fixture sun events: astronomical night ends at hour 21 next calendar day
        // (Phase4BFixtures hour(21, dayOffset: 1) as night end via tomorrow's twilight).
        // 01:00 next calendar day is still inside that night for these fixtures when
        // previous-night window is active (matches Tonight Targets widget tests).
        let afterMidnight = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026, month: 6, day: 2, hour: 1
        ))!

        let conditions = Phase4BFixtures.analyzableConditions(
            locationID: id,
            referenceDate: evening
        )
        XCTAssertFalse(
            calendar.isDate(conditions.fetchedAt, inSameDayAs: afterMidnight),
            "fixture crosses calendar midnight"
        )
        XCTAssertTrue(
            conditions.isFresh(
                within: WatchComplicationCompanionDisplayPolicy.companionDisplayMaxAge,
                relativeTo: afterMidnight
            )
        )

        // Calendar-day freshness would wrongly reject; active-night policy must not.
        XCTAssertFalse(
            conditions.isFreshForLocalDay(
                within: WatchComplicationCompanionDisplayPolicy.companionDisplayMaxAge,
                relativeTo: afterMidnight
            )
        )

        let result = WatchComplicationCompanionDisplayPolicy.evaluate(
            selectedLocation: selectedLocation(id: id),
            conditions: conditions,
            referenceDate: afterMidnight
        )
        guard case let .success(context) = result else {
            return XCTFail("active astronomical night after midnight must display, got \(result)")
        }
        // Observing date remains the evening's local day, not the post-midnight calendar day.
        XCTAssertTrue(
            calendar.isDate(context.activeNight.observingDate, inSameDayAs: evening),
            "ActiveObservingNight should keep previous observing date after midnight"
        )
        XCTAssertTrue(
            afterMidnight >= context.activeNight.context.astronomicalNightStart
                && afterMidnight <= context.activeNight.context.astronomicalNightEnd
        )
    }

    /// After the astronomical night has ended, a payload that can no longer resolve
    /// Tonight (requires previous night that is already over / unavailable) is hidden.
    func testPriorObservingNightPairUnavailableAfterNightEndedWithoutNextContext() {
        let id = UUID()
        let evening = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026, month: 6, day: 1, hour: 21
        ))!
        // Only one local day of astronomy — cannot pivot to the next evening's night.
        let conditions = makeSingleDayConditions(locationID: id, referenceDate: evening)

        // Morning well after astronomical night end for that single day.
        let nextMorning = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026, month: 6, day: 2, hour: 10
        ))!

        let active = ActiveObservingNightResolver.resolve(
            conditions: conditions,
            referenceDate: nextMorning,
            timeZone: calendar.timeZone
        )
        // Single-day payload cannot resolve a usable Tonight after the night ends.
        if case .resolved = active {
            return XCTFail("single-day fixture expected not to resolve next Tonight; got \(active)")
        }

        let result = WatchComplicationCompanionDisplayPolicy.evaluate(
            selectedLocation: selectedLocation(id: id),
            conditions: conditions,
            referenceDate: nextMorning
        )
        guard case .failure(.inactiveObservingNight) = result else {
            return XCTFail("ended night without next context must be unavailable, got \(result)")
        }
    }

    func testCompanionStillDisplayableSameEveningWithin24hBeyondRefreshGate() {
        let id = UUID()
        let earlyEvening = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026, month: 6, day: 1, hour: 18
        ))!
        let lateEvening = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026, month: 6, day: 1, hour: 22
        ))!
        let conditions = Phase4BFixtures.analyzableConditions(
            locationID: id,
            referenceDate: earlyEvening
        )
        XCTAssertFalse(
            conditions.isFreshForLocalDay(
                within: WatchConditionsPushAcceptance.freshConditionsInterval,
                relativeTo: lateEvening
            ),
            "fixture must sit outside the 1h watch refresh gate"
        )
        let result = WatchComplicationCompanionDisplayPolicy.evaluate(
            selectedLocation: selectedLocation(id: id),
            conditions: conditions,
            referenceDate: lateEvening
        )
        guard case .success = result else {
            return XCTFail("same evening within 24h must display, got \(result)")
        }
    }

    func testCompanionDisplayMaxAgeIsTwentyFourHoursNotOneHourRefreshGate() {
        XCTAssertEqual(
            WatchComplicationCompanionDisplayPolicy.companionDisplayMaxAge,
            24 * 3600
        )
        XCTAssertNotEqual(
            WatchComplicationCompanionDisplayPolicy.companionDisplayMaxAge,
            WatchConditionsPushAcceptance.freshConditionsInterval
        )
        XCTAssertEqual(WatchConditionsPushAcceptance.freshConditionsInterval, 3600)
    }

    /// Evening OQ pair (night 98 → OQ 91 with home LP) must stay OQ-backed after midnight
    /// while still inside the same active astronomical night — not demote to night-only 98.
    func testCrossMidnightKeepsOQHeadlineNotNightOnlyFallback() throws {
        let id = UUID()
        let evening = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026, month: 6, day: 1, hour: 21
        ))!
        let afterMidnight = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026, month: 6, day: 2, hour: 1
        ))!

        // Clear night → night score 98 with Phase4B sun/forecast fixtures.
        let conditions = try makeConditionsWithNightScore(
            98,
            locationID: id,
            referenceDate: evening
        )
        let selected = selectedLocation(id: id)

        // Evening: active night + persisted OQ at brightness 18.5 (base LP penalty 7).
        guard case let .resolved(eveningActive) = ActiveObservingNightResolver.resolve(
            conditions: conditions,
            referenceDate: evening,
            timeZone: calendar.timeZone
        ) else {
            return XCTFail("evening must resolve active observing night")
        }
        let eveningNightScore = eveningActive.context.nightQuality.calculatedScore
        XCTAssertEqual(eveningNightScore, 98)

        let document = try makePersistedOQDocument(
            conditions: conditions,
            locationID: id,
            nightScore: eveningNightScore,
            brightness: 18.5
        )
        XCTAssertEqual(document.associatedNightConditionsScore, 98)
        XCTAssertEqual(document.snapshot.nightConditionsScore, 98)
        XCTAssertEqual(document.snapshot.observingQualityScore, 91)
        XCTAssertEqual(document.snapshot.brightnessAvailability, .available)

        // After midnight: same active night, still displayable.
        let display = WatchComplicationCompanionDisplayPolicy.evaluate(
            selectedLocation: selected,
            conditions: conditions,
            referenceDate: afterMidnight
        )
        guard case let .success(context) = display else {
            return XCTFail("after midnight during active night must display, got \(display)")
        }
        XCTAssertTrue(
            calendar.isDate(
                context.activeNight.observingDate,
                inSameDayAs: eveningActive.observingDate
            ),
            "must keep the evening observing date across midnight"
        )
        let activeNightScore = context.activeNight.context.nightQuality.calculatedScore
        XCTAssertEqual(
            activeNightScore,
            eveningNightScore,
            "active-night Night Conditions score must be stable across midnight"
        )
        XCTAssertEqual(activeNightScore, 98)

        // Headline uses the same production path as the complication (active-night score).
        let headline = WatchComplicationHeadlineResolver.resolve(
            conditions: context.conditions,
            document: document,
            selectedLocation: context.selected,
            nightScore: activeNightScore
        )
        XCTAssertEqual(
            headline.presentationMode,
            .observingQuality,
            "must not fall back to night-only merely because the calendar date changed"
        )
        XCTAssertEqual(headline.score, 91)
        XCTAssertNotEqual(
            headline.score,
            98,
            "must not surface raw night-only score when OQ association remains valid"
        )
    }

    // MARK: - Helpers

    private func selectedLocation(id: UUID) -> SelectedLocation {
        Phase4BFixtures.selectedSaved(id: id)
    }

    /// Conditions with astronomy for a single local day only (no next-night pivot).
    private func makeSingleDayConditions(
        locationID: UUID,
        referenceDate: Date
    ) -> ViewingConditions {
        let full = Phase4BFixtures.analyzableConditions(
            locationID: locationID,
            referenceDate: referenceDate
        )
        return ViewingConditions(
            fetchedAt: full.fetchedAt,
            location: full.location,
            hourlyForecasts: full.hourlyForecasts,
            dailySunEvents: Array(full.dailySunEvents.prefix(1)),
            dailyMoonInfo: Array(full.dailyMoonInfo.prefix(1)),
            issPasses: [],
            fogScore: full.fogScore,
            timeZoneIdentifier: full.timeZoneIdentifier
        )
    }

    /// Brute-force cloud cover so ActiveObservingNight night score matches `target`.
    private func makeConditionsWithNightScore(
        _ target: Int,
        locationID: UUID,
        referenceDate: Date
    ) throws -> ViewingConditions {
        for cloud in 0...100 {
            let conditions = Phase4BFixtures.analyzableConditions(
                locationID: locationID,
                referenceDate: referenceDate,
                cloudCover: cloud
            )
            guard case let .resolved(active) = ActiveObservingNightResolver.resolve(
                conditions: conditions,
                referenceDate: referenceDate,
                timeZone: calendar.timeZone
            ) else { continue }
            if active.context.nightQuality.calculatedScore == target {
                return conditions
            }
        }
        struct NightScoreNotFound: Error {}
        throw NightScoreNotFound()
    }

    private func makePersistedOQDocument(
        conditions: ViewingConditions,
        locationID: UUID,
        nightScore: Int,
        brightness: Double
    ) throws -> WatchObservingQualityDocument {
        let location = try XCTUnwrap(CrossSurfaceLocationContext.make(
            from: Phase4BFixtures.selectedSaved(id: locationID)
        ))
        // sampledAt must not be after assessedAt (`now` in validity); use conditions epoch.
        let sample = ModeledZenithBrightnessSample(
            latitude: location.latitude,
            longitude: location.longitude,
            modeledZenithSkyBrightness: brightness,
            dataset: Phase4BFixtures.dataset(),
            sampledAt: conditions.fetchedAt,
            savedLocationID: locationID
        )
        let snapshot = CrossSurfaceObservingQualityResolver.resolve(
            .init(
                nightConditionsScore: nightScore,
                location: location,
                sample: sample,
                assessedAt: conditions.fetchedAt
            )
        )
        XCTAssertEqual(snapshot.brightnessAvailability, .available)
        return WatchObservingQualityDocument(
            snapshot: snapshot,
            location: location,
            associatedNightConditionsScore: nightScore,
            associatedConditionsLocationID: conditions.location.id,
            associatedLatitude: conditions.location.latitude,
            associatedLongitude: conditions.location.longitude
        )
    }
}

final class WatchComplicationHeadlineResolverTests: XCTestCase {
    func testMissingDocumentFallsBackToNightScore() {
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        let night = Phase4BFixtures.nightScore(for: conditions)
        let resolved = WatchComplicationHeadlineResolver.resolve(
            conditions: conditions,
            document: nil,
            selectedLocation: Phase4BFixtures.selectedSaved(id: id),
            nightScore: night
        )
        XCTAssertEqual(resolved.score, night)
        XCTAssertEqual(resolved.presentationMode, .nightConditionsFallback)
    }

    func testAssociatedDocumentUsesObservingQualityScore() {
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        let night = Phase4BFixtures.nightScore(for: conditions)
        let payload = Phase4BFixtures.validPayload(id: id, conditions: conditions)
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4BFixtures.selectedSaved(id: id)
        )
        guard case .enhanced = outcome,
              let document = WatchObservingQualityCanonicalizer.document(
                from: outcome,
                conditions: conditions
              )
        else {
            return XCTFail("fixture requires enhanced document")
        }
        let resolved = WatchComplicationHeadlineResolver.resolve(
            conditions: conditions,
            document: document,
            selectedLocation: Phase4BFixtures.selectedSaved(id: id),
            nightScore: night
        )
        XCTAssertEqual(resolved.presentationMode, .observingQuality)
        XCTAssertEqual(resolved.score, document.snapshot.observingQualityScore)
        XCTAssertNotEqual(
            resolved.score,
            night,
            "home LP penalty fixture should differ from raw night score"
        )
    }

    func testUnassociatedDocumentFallsBackToNightScore() {
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        let other = Phase4BFixtures.analyzableConditions(
            locationID: UUID(),
            lat: 47.6,
            lon: -122.3
        )
        let night = Phase4BFixtures.nightScore(for: other)
        let payload = Phase4BFixtures.validPayload(id: id, conditions: conditions)
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4BFixtures.selectedSaved(id: id)
        )
        guard case .enhanced = outcome,
              let document = WatchObservingQualityCanonicalizer.document(
                from: outcome,
                conditions: conditions
              )
        else {
            return XCTFail("fixture requires enhanced document")
        }
        let resolved = WatchComplicationHeadlineResolver.resolve(
            conditions: other,
            document: document,
            selectedLocation: Phase4BFixtures.selectedSaved(id: UUID()),
            nightScore: night
        )
        XCTAssertEqual(resolved.score, night)
        XCTAssertEqual(resolved.presentationMode, .nightConditionsFallback)
    }
}

final class WatchComplicationUnavailablePresentationTests: XCTestCase {
    func testUnavailablePresentationIsNonNumeric() {
        XCTAssertEqual(WatchComplicationUnavailablePresentation.scoreText, "--")
        XCTAssertEqual(
            WatchComplicationUnavailablePresentation.accessibilityLabel,
            "Night conditions unavailable"
        )
        XCTAssertFalse(
            WatchComplicationUnavailablePresentation.scoreText.contains(where: \.isNumber),
            "unavailable must not show a fabricated numeric score"
        )
    }
}

final class WatchComplicationWidgetSourceGuardrailTests: XCTestCase {
    func testLivePathsUseUnavailableNotPlaceholderAndRemainReadOnly() throws {
        let source = try sourceText("Sources/WatchWidget/NightConditionsWatchWidget.swift")

        // Read-only companion: no independent fetch / unpaired write / GPS.
        XCTAssertFalse(source.contains("ConditionsProvider()"))
        XCTAssertFalse(source.contains("saveWatchNightConditions"))
        XCTAssertFalse(source.contains("LocationManager()"))
        XCTAssertTrue(source.contains("loadWatchNightConditionsAsync"))
        XCTAssertTrue(source.contains("loadWatchObservingQualityAsync"))
        XCTAssertTrue(source.contains("WatchComplicationCompanionDisplayPolicy"))
        XCTAssertTrue(
            source.contains("activeNight") || source.contains("WatchComplicationCompanionDisplayContext"),
            "complication must use ActiveObservingNight-selected context for scoring"
        )

        // Live timeline/snapshot must not fall back to synthetic placeholder.
        XCTAssertFalse(source.contains("buildEntry() ?? .placeholder"))
        XCTAssertFalse(source.contains("?? .placeholder"))
        XCTAssertTrue(source.contains(".unavailable"))
        XCTAssertTrue(source.contains("case unavailable"))

        // Gallery placeholder path remains explicit and separate.
        XCTAssertTrue(source.contains("func placeholder(in context: Context)"))
        XCTAssertTrue(source.contains("completion(.placeholder)"))
        XCTAssertTrue(source.contains("static var placeholder"))
        XCTAssertTrue(source.contains("context.isPreview"))
        XCTAssertTrue(source.contains(".unavailable(at:"))

        // No calendar-day freshness for companion gate (policy owns ActiveObservingNight).
        let policySource = try sourceText(
            "Sources/SharedCode/Core/Models/WatchComplicationCompanion.swift"
        )
        XCTAssertFalse(
            policySource.contains("isFreshForLocalDay"),
            "companion policy must not use calendar-day freshness"
        )
        XCTAssertTrue(policySource.contains("ActiveObservingNightResolver"))
        XCTAssertTrue(policySource.contains("isFresh("))
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
}

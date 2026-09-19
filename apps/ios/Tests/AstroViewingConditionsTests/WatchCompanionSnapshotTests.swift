@testable import SharedCode
import XCTest

final class WatchCompanionSnapshotCodecTests: XCTestCase {
    func testRoundTripPreservesAllFields() throws {
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        let selected = Phase4BFixtures.selectedSaved(id: id)
        let payload = Phase4BFixtures.validPayload(id: id, conditions: conditions)
        let locations = [conditions.location]
        let samples = [Phase4BFixtures.sample(id: id)]
        let publishedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let snapshot = WatchCompanionSnapshot(
            selectedLocation: selected,
            locations: locations,
            conditions: conditions,
            observingQuality: payload,
            unitSystem: .imperial,
            modeledBrightnessSamples: samples,
            publishedAt: publishedAt
        )
        let encoded = try XCTUnwrap(WatchCompanionSnapshotCodec.encode(snapshot))
        XCTAssertEqual(
            encoded[WatchCompanionSnapshotCodec.typeKey] as? String,
            WatchCompanionSnapshotCodec.messageType
        )
        let decoded = try XCTUnwrap(WatchCompanionSnapshotCodec.decode(encoded))
        XCTAssertEqual(decoded.selectedLocation, selected)
        XCTAssertEqual(decoded.locations?.count, 1)
        XCTAssertEqual(decoded.locations?.first?.id, id)
        XCTAssertEqual(decoded.conditions?.fetchedAt, conditions.fetchedAt)
        XCTAssertEqual(decoded.observingQuality?.location.savedLocationID, id)
        XCTAssertEqual(decoded.unitSystem, .imperial)
        XCTAssertEqual(decoded.modeledBrightnessSamples.count, 1)
        XCTAssertEqual(decoded.publishedAt, publishedAt)
    }

    func testCorruptConditionsFieldDoesNotDropUnitsOrLocations() throws {
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        var encoded = try XCTUnwrap(
            WatchCompanionSnapshotCodec.encode(
                WatchCompanionSnapshot(
                    selectedLocation: Phase4BFixtures.selectedSaved(id: id),
                    locations: [conditions.location],
                    conditions: conditions,
                    unitSystem: .metric
                )
            )
        )
        encoded[WatchCompanionSnapshotCodec.conditionsKey] = Data("not-json".utf8)

        let decoded = try XCTUnwrap(WatchCompanionSnapshotCodec.decode(encoded))
        XCTAssertNil(decoded.conditions)
        XCTAssertEqual(decoded.unitSystem, .metric)
        XCTAssertEqual(decoded.locations?.count, 1)
        XCTAssertEqual(decoded.selectedLocation?.id, id)
    }

    func testLegacyUnitsDictionaryDoesNotImplyConditions() {
        let encoded = try! JSONEncoder().encode(UnitSystem.imperial.rawValue)
        let legacy: [String: Any] = [
            "type": "unitSystem",
            "unitSystem": encoded,
        ]
        let snapshot = try! XCTUnwrap(WatchCompanionSnapshotCodec.decodeLegacy(legacy))
        XCTAssertEqual(snapshot.unitSystem, .imperial)
        XCTAssertNil(snapshot.conditions)
        XCTAssertNil(snapshot.locations)
        XCTAssertNil(snapshot.selectedLocation)
    }

    func testUnknownTypeIsNotASnapshot() {
        XCTAssertNil(WatchCompanionSnapshotCodec.decode(["type": "unitSystem"]))
        XCTAssertNil(WatchCompanionSnapshotCodec.decodeLegacy(["type": "companionSnapshot"]))
        XCTAssertNil(WatchCompanionSnapshotCodec.decodeAny(["type": "nope"]))
    }
}

final class WatchCompanionSnapshotApplyPolicyTests: XCTestCase {
    func testUnitsOnlySnapshotDoesNotReplaceConditions() {
        let snapshot = WatchCompanionSnapshot(unitSystem: .imperial)
        let plan = WatchCompanionSnapshotApplyPolicy.plan(
            snapshot: snapshot,
            selectedLocation: Phase4BFixtures.selectedSaved(id: UUID())
        )
        XCTAssertEqual(plan.unitSystem, .imperial)
        XCTAssertFalse(plan.replacesConditions)
        XCTAssertNil(plan.conditions)
        XCTAssertNil(plan.locations)
    }

    func testLocationsOnlySnapshotDoesNotReplaceConditions() {
        let id = UUID()
        let location = Phase4BFixtures.analyzableConditions(locationID: id).location
        let snapshot = WatchCompanionSnapshot(locations: [location])
        let plan = WatchCompanionSnapshotApplyPolicy.plan(
            snapshot: snapshot,
            selectedLocation: Phase4BFixtures.selectedSaved(id: id)
        )
        XCTAssertEqual(plan.locations?.first?.id, id)
        XCTAssertFalse(plan.replacesConditions)
    }

    func testFreshMatchingConditionsAreApplied() {
        let id = UUID()
        let now = Date()
        let conditions = Phase4BFixtures.analyzableConditions(
            locationID: id,
            referenceDate: now
        )
        let selected = Phase4BFixtures.selectedSaved(id: id)
        let oq = Phase4BFixtures.validPayload(id: id, conditions: conditions)
        let snapshot = WatchCompanionSnapshot(
            selectedLocation: selected,
            conditions: conditions,
            observingQuality: oq,
            unitSystem: .metric
        )
        let plan = WatchCompanionSnapshotApplyPolicy.plan(
            snapshot: snapshot,
            selectedLocation: selected,
            now: now
        )
        XCTAssertTrue(plan.replacesConditions)
        XCTAssertEqual(plan.conditions?.fetchedAt, conditions.fetchedAt)
        XCTAssertNotNil(plan.observingQuality)
        XCTAssertEqual(plan.unitSystem, .metric)
    }

    func testStaleConditionsInSnapshotDoNotReplaceLastKnownPair() {
        let id = UUID()
        let evening = calendarDate(year: 2026, month: 6, day: 1, hour: 21)
        let conditions = Phase4BFixtures.analyzableConditions(
            locationID: id,
            referenceDate: evening
        )
        let selected = Phase4BFixtures.selectedSaved(id: id)
        let snapshot = WatchCompanionSnapshot(
            selectedLocation: selected,
            locations: [conditions.location],
            conditions: conditions,
            unitSystem: .imperial
        )
        let plan = WatchCompanionSnapshotApplyPolicy.plan(
            snapshot: snapshot,
            selectedLocation: selected,
            now: evening.addingTimeInterval(
                WatchConditionsPushAcceptance.freshConditionsInterval + 60
            )
        )
        XCTAssertEqual(plan.unitSystem, .imperial)
        XCTAssertEqual(plan.locations?.count, 1)
        XCTAssertFalse(plan.replacesConditions)
        XCTAssertNil(plan.conditions)
    }

    func testMismatchedLocationConditionsAreNotApplied() {
        let id = UUID()
        let now = Date()
        let conditions = Phase4BFixtures.analyzableConditions(
            locationID: UUID(),
            lat: Phase4BFixtures.latitude + 1,
            referenceDate: now
        )
        let selected = Phase4BFixtures.selectedSaved(id: id)
        let snapshot = WatchCompanionSnapshot(
            selectedLocation: selected,
            conditions: conditions
        )
        let plan = WatchCompanionSnapshotApplyPolicy.plan(
            snapshot: snapshot,
            selectedLocation: selected,
            now: now
        )
        XCTAssertFalse(plan.replacesConditions)
    }

    func testAccumulatorKeepsConditionsWhenLaterUnitsArePublished() {
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        var accumulator = WatchCompanionSnapshotAccumulator()
        accumulator.setConditions(conditions, observingQuality: nil)
        accumulator.setUnitSystem(.imperial)
        let snapshot = accumulator.snapshot()
        XCTAssertEqual(snapshot.unitSystem, .imperial)
        XCTAssertEqual(snapshot.conditions?.fetchedAt, conditions.fetchedAt)
    }

    func testSelectingADifferentLocationDropsCarriedConditions() {
        let a = UUID()
        let b = UUID()
        let conditionsA = Phase4BFixtures.analyzableConditions(locationID: a)
        var accumulator = WatchCompanionSnapshotAccumulator()
        accumulator.setSelectedLocation(Phase4BFixtures.selectedSaved(id: a))
        accumulator.setConditions(conditionsA, observingQuality: nil)
        accumulator.setSelectedLocation(Phase4BFixtures.selectedSaved(id: b))
        XCTAssertNil(accumulator.conditions)
        XCTAssertNil(accumulator.observingQuality)
        XCTAssertEqual(accumulator.selectedLocation?.id, b)
    }

    private func calendarDate(year: Int, month: Int, day: Int, hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: Phase4BFixtures.timeZoneID)!
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year, month: month, day: day, hour: hour
        ))!
    }
}

final class WatchCompanionPendingContextTests: XCTestCase {
    func testBackgroundConsumptionAppliesBThenBindsBNeverAcquiresA() {
        let locationA = Phase4BFixtures.selectedSaved(id: UUID())
        let locationB = Phase4BFixtures.selectedSaved(id: UUID())
        let conditionsA = Phase4BFixtures.analyzableConditions(locationID: locationA.id)
        let snapshot = WatchCompanionSnapshot(selectedLocation: locationB)

        var appliedSelection: SelectedLocation?
        var acquired: [SelectedLocation] = []

        let bound = WatchCompanionPendingContext.consumeThenBind(
            snapshot: snapshot,
            currentSelectedLocation: locationA
        ) { plan in
            XCTAssertTrue(
                acquired.isEmpty,
                "acquisition must not start before snapshot apply finishes"
            )
            appliedSelection = plan.selectedLocation
        }

        XCTAssertEqual(appliedSelection, locationB)
        XCTAssertEqual(bound, locationB)
        XCTAssertNotEqual(bound, locationA)

        let decision = WatchBackgroundRefreshPolicy.decide(
            selectedLocation: bound,
            conditions: conditionsA
        )
        if case let .refresh(location) = decision {
            acquired.append(location)
        }

        XCTAssertEqual(acquired, [locationB])
        XCTAssertFalse(acquired.contains(locationA))
        XCTAssertEqual(decision.selectedLocation, locationB)
    }

    func testLegacyConditionsWithoutSelectionAreAcceptedForCurrentLocationA() throws {
        let locationA = Phase4BFixtures.selectedSaved(id: UUID())
        let now = Date()
        let conditionsA = Phase4BFixtures.analyzableConditions(
            locationID: locationA.id,
            referenceDate: now
        )
        let snapshot = try Self.legacyConditionsSnapshot(
            conditions: conditionsA,
            observingQuality: Phase4BFixtures.validPayload(
                id: locationA.id!,
                conditions: conditionsA
            )
        )
        XCTAssertNil(snapshot.selectedLocation)
        XCTAssertNotNil(snapshot.conditions)

        var appliedConditions: Date?
        var appliedSelection: SelectedLocation?
        let bound = WatchCompanionPendingContext.consumeThenBind(
            snapshot: snapshot,
            currentSelectedLocation: locationA,
            apply: { plan in
                appliedSelection = plan.selectedLocation
                appliedConditions = plan.conditions?.fetchedAt
            }
        )

        XCTAssertNil(
            appliedSelection,
            "legacy conditions must not invent a selection change"
        )
        XCTAssertEqual(appliedConditions, conditionsA.fetchedAt)
        XCTAssertEqual(bound, locationA)
    }

    func testLegacyConditionsWithoutSelectionAreRejectedForDifferentLocationB() throws {
        let locationA = Phase4BFixtures.selectedSaved(id: UUID())
        let locationB = Phase4BFixtures.selectedSaved(id: UUID())
        let now = Date()
        let conditionsB = Phase4BFixtures.analyzableConditions(
            locationID: locationB.id,
            referenceDate: now
        )
        let snapshot = try Self.legacyConditionsSnapshot(conditions: conditionsB)
        XCTAssertNil(snapshot.selectedLocation)

        var appliedConditions = false
        let bound = WatchCompanionPendingContext.consumeThenBind(
            snapshot: snapshot,
            currentSelectedLocation: locationA,
            apply: { plan in
                appliedConditions = plan.replacesConditions
            }
        )

        XCTAssertFalse(appliedConditions)
        XCTAssertEqual(bound, locationA)
    }

    func testLegacyLocationsWithoutSelectionDoNotTreatCurrentAsASelectionChange() throws {
        let locationA = Phase4BFixtures.selectedSaved(id: UUID())
        let pin = Phase4BFixtures.analyzableConditions(locationID: locationA.id).location
        let payload: [String: Any] = [
            WatchCompanionSnapshotCodec.typeKey: "savedLocations",
            WatchCompanionSnapshotCodec.locationsKey: try JSONEncoder().encode([pin]),
        ]
        let snapshot = try XCTUnwrap(WatchCompanionSnapshotCodec.decodeLegacy(payload))
        XCTAssertNil(snapshot.selectedLocation)

        var appliedSelection: SelectedLocation?
        var appliedLocationCount = 0
        let bound = WatchCompanionPendingContext.consumeThenBind(
            snapshot: snapshot,
            currentSelectedLocation: locationA
        ) { plan in
            appliedSelection = plan.selectedLocation
            appliedLocationCount = plan.locations?.count ?? 0
        }

        XCTAssertEqual(appliedLocationCount, 1)
        XCTAssertNil(appliedSelection)
        XCTAssertEqual(bound, locationA)
    }

    func testFullSnapshotSelectionBWinsOverCurrentAAndKeepsApplyThenBindOrder() {
        let locationA = Phase4BFixtures.selectedSaved(id: UUID())
        let locationB = Phase4BFixtures.selectedSaved(id: UUID())
        let now = Date()
        let conditionsB = Phase4BFixtures.analyzableConditions(
            locationID: locationB.id,
            referenceDate: now
        )
        let snapshot = WatchCompanionSnapshot(
            selectedLocation: locationB,
            conditions: conditionsB
        )

        var appliedSelection: SelectedLocation?
        var acquired: [SelectedLocation] = []
        let bound = WatchCompanionPendingContext.consumeThenBind(
            snapshot: snapshot,
            currentSelectedLocation: locationA
        ) { plan in
            XCTAssertTrue(acquired.isEmpty)
            XCTAssertTrue(plan.replacesConditions)
            appliedSelection = plan.selectedLocation
        }

        XCTAssertEqual(appliedSelection, locationB)
        XCTAssertEqual(bound, locationB)
        XCTAssertNotEqual(bound, locationA)

        if let bound {
            acquired.append(bound)
        }
        XCTAssertEqual(acquired, [locationB])
    }

    private static func legacyConditionsSnapshot(
        conditions: ViewingConditions,
        observingQuality: WatchObservingQualityPayload? = nil
    ) throws -> WatchCompanionSnapshot {
        var payload: [String: Any] = [
            WatchCompanionSnapshotCodec.typeKey: "conditions",
            WatchCompanionSnapshotCodec.conditionsKey: try JSONEncoder().encode(conditions),
        ]
        if let observingQuality {
            payload[WatchCompanionSnapshotCodec.observingQualityKey] =
                try JSONEncoder().encode(observingQuality)
        }
        return try XCTUnwrap(WatchCompanionSnapshotCodec.decodeLegacy(payload))
    }
}

final class WatchCompanionSnapshotReseedTests: XCTestCase {
    func testProcessReseedKeepsMatchingConditionsWhenOnlyUnitsChange() {
        let id = UUID()
        let selected = Phase4BFixtures.selectedSaved(id: id)
        let now = Date()
        let conditions = Phase4BFixtures.analyzableConditions(
            locationID: id,
            referenceDate: now
        )
        let oq = Phase4BFixtures.validPayload(id: id, conditions: conditions)
        let previouslyPublished = WatchCompanionSnapshot(
            selectedLocation: selected,
            locations: [conditions.location],
            conditions: conditions,
            observingQuality: oq,
            unitSystem: .metric
        )

        var rebuildCount = 0
        let restored = WatchCompanionSnapshotReseed.restoredConditions(
            selectedLocation: selected,
            sessionSnapshot: previouslyPublished,
            repositoryConditions: nil,
            rebuildObservingQuality: { _, _ in
                rebuildCount += 1
                return nil
            }
        )
        XCTAssertEqual(rebuildCount, 0, "matching session OQ must be kept, not rebuilt")

        var reconstructed = WatchCompanionSnapshotAccumulator(
            selectedLocation: selected,
            locations: [conditions.location],
            unitSystem: .imperial
        )
        if let restored {
            reconstructed.setConditions(restored.conditions, observingQuality: restored.observingQuality)
        }
        reconstructed.setUnitSystem(.imperial)

        let published = reconstructed.snapshot()
        XCTAssertEqual(published.unitSystem, .imperial)
        XCTAssertEqual(published.selectedLocation, selected)
        XCTAssertEqual(published.conditions?.fetchedAt, conditions.fetchedAt)
        XCTAssertEqual(
            published.observingQuality?.location.savedLocationID,
            oq.location.savedLocationID
        )
    }

    func testProcessReseedDoesNotCarryConditionsForADifferentSelection() {
        let selectedA = Phase4BFixtures.selectedSaved(id: UUID())
        let selectedB = Phase4BFixtures.selectedSaved(id: UUID())
        let conditionsA = Phase4BFixtures.analyzableConditions(locationID: selectedA.id)
        let sessionSnapshot = WatchCompanionSnapshot(
            selectedLocation: selectedA,
            conditions: conditionsA,
            observingQuality: Phase4BFixtures.validPayload(
                id: selectedA.id!,
                conditions: conditionsA
            )
        )

        var rebuilt = false
        let restored = WatchCompanionSnapshotReseed.restoredConditions(
            selectedLocation: selectedB,
            sessionSnapshot: sessionSnapshot,
            repositoryConditions: conditionsA,
            rebuildObservingQuality: { _, _ in
                rebuilt = true
                return nil
            }
        )
        XCTAssertNil(restored)
        XCTAssertFalse(rebuilt, "mismatched conditions must not be rebuilt for another location")
    }

    func testProcessReseedFallsBackToMatchingRepositoryConditions() {
        let id = UUID()
        let selected = Phase4BFixtures.selectedSaved(id: id)
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        let rebuiltOQ = Phase4BFixtures.validPayload(id: id, conditions: conditions)

        let restored = WatchCompanionSnapshotReseed.restoredConditions(
            selectedLocation: selected,
            sessionSnapshot: WatchCompanionSnapshot(unitSystem: .metric),
            repositoryConditions: conditions,
            rebuildObservingQuality: { restoredConditions, restoredSelected in
                XCTAssertEqual(restoredSelected, selected)
                XCTAssertEqual(restoredConditions.fetchedAt, conditions.fetchedAt)
                return rebuiltOQ
            }
        )
        XCTAssertEqual(restored?.conditions.fetchedAt, conditions.fetchedAt)
        XCTAssertEqual(restored?.observingQuality?.location.savedLocationID, id)
    }
}

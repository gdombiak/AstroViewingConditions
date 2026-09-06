import XCTest
@testable import AstroEngine

final class DeepSkyObservationTests: XCTestCase {
    private func date(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: text)!
    }

    private func sample(_ offsetMinutes: Double, _ altitude: Double, _ azimuth: Double = 90) -> DeepSkyObservation.Sample {
        DeepSkyObservation.Sample(
            time: date("2026-09-06T00:00:00Z").addingTimeInterval(offsetMinutes * 60),
            altitude: altitude,
            azimuth: azimuth
        )
    }

    // MARK: - Sampling

    func testInclusiveEndpointSamplingStopsEarlyOnIndivisibleIntervals() {
        let start = date("2026-09-06T01:00:00Z")
        let rows = DeepSkyObservation.samples(
            rightAscensionHours: 16.6949, declinationDegrees: 36.4613,
            latitudeDegrees: 40, longitudeDegrees: -74,
            start: start, end: start.addingTimeInterval(50 * 60)
        )
        XCTAssertEqual(rows.map(\.time), [0, 900, 1800, 2700].map(start.addingTimeInterval))
    }

    func testInvertedIntervalHasNoSamplesAndZeroLengthHasOne() {
        let start = date("2026-09-06T01:00:00Z")
        XCTAssertTrue(DeepSkyObservation.samples(
            rightAscensionHours: 0, declinationDegrees: 0, latitudeDegrees: 0, longitudeDegrees: 0,
            start: start, end: start.addingTimeInterval(-1)
        ).isEmpty)
        XCTAssertEqual(DeepSkyObservation.samples(
            rightAscensionHours: 0, declinationDegrees: 0, latitudeDegrees: 0, longitudeDegrees: 0,
            start: start, end: start
        ).count, 1)
    }

    // MARK: - Runs

    func testThresholdEqualityIsVisible() {
        let rows = [sample(0, 10), sample(15, 15), sample(30, 10)]
        let windows = DeepSkyObservation.windows(
            from: rows, intervalStart: rows[0].time, intervalEnd: rows[2].time, minimumAltitude: 15
        )
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].maxAltitude, 15)
        XCTAssertEqual(windows[0].bestTime, rows[1].time)
    }

    func testHighestAltitudeTieKeepsTheEarliestSample() {
        let rows = [sample(0, 20, 90), sample(15, 30, 100), sample(30, 30, 200), sample(45, 20, 260)]
        let windows = DeepSkyObservation.windows(
            from: rows, intervalStart: rows[0].time, intervalEnd: rows[3].time, minimumAltitude: 15
        )
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].bestTime, rows[1].time)
        XCTAssertEqual(windows[0].azimuth, 100)
        XCTAssertEqual(windows[0].direction, "E")
    }

    func testMultipleRunsEachProduceAWindow() {
        let rows = [sample(0, 20), sample(15, 5), sample(30, 20), sample(45, 5)]
        let windows = DeepSkyObservation.windows(
            from: rows, intervalStart: rows[0].time, intervalEnd: rows[3].time, minimumAltitude: 15
        )
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].start, rows[0].time)
        XCTAssertEqual(windows[1].end, DeepSkyObservation.thresholdCrossing(
            between: rows[2], and: rows[3], minimumAltitude: 15
        ))
    }

    func testNeverVisibleAndAllVisibleBoundaries() {
        let rows = [sample(0, 5), sample(15, 6)]
        XCTAssertTrue(DeepSkyObservation.windows(
            from: rows, intervalStart: rows[0].time, intervalEnd: rows[1].time, minimumAltitude: 15
        ).isEmpty)

        let visible = [sample(0, 40), sample(15, 45)]
        let intervalEnd = visible[1].time.addingTimeInterval(600)
        let windows = DeepSkyObservation.windows(
            from: visible, intervalStart: visible[0].time, intervalEnd: intervalEnd, minimumAltitude: 15
        )
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].start, visible[0].time)
        // Preserved quirk: a run reaching the last sample reports the interval end,
        // which here is later than the last instant actually evaluated.
        XCTAssertEqual(windows[0].end, intervalEnd)
    }

    func testSingleSampleRunIsAWindow() {
        let rows = [sample(0, 5), sample(15, 40), sample(30, 5)]
        let windows = DeepSkyObservation.windows(
            from: rows, intervalStart: rows[0].time, intervalEnd: rows[2].time, minimumAltitude: 15
        )
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].bestTime, rows[1].time)
        XCTAssertLessThan(windows[0].start, windows[0].end)
    }

    // MARK: - Crossing

    func testDegenerateSlopeGuardReturnsTheFirstInstant() {
        let flat = (sample(0, 20), sample(15, 20.00005))
        XCTAssertEqual(
            DeepSkyObservation.thresholdCrossing(between: flat.0, and: flat.1, minimumAltitude: 15),
            flat.0.time
        )
    }

    func testCrossingFractionIsClampedIntoThePair() {
        // Both samples already above threshold: the unclamped fraction is negative.
        let pair = (sample(0, 20), sample(15, 30))
        XCTAssertEqual(
            DeepSkyObservation.thresholdCrossing(between: pair.0, and: pair.1, minimumAltitude: 15),
            pair.0.time
        )
        // Both below with a rising slope: the unclamped fraction exceeds 1.
        let low = (sample(0, 1), sample(15, 2))
        XCTAssertEqual(
            DeepSkyObservation.thresholdCrossing(between: low.0, and: low.1, minimumAltitude: 15),
            low.1.time
        )
    }

    func testInteriorCrossingInterpolatesLinearly() {
        let pair = (sample(0, 10), sample(20, 30))
        XCTAssertEqual(
            DeepSkyObservation.thresholdCrossing(between: pair.0, and: pair.1, minimumAltitude: 15),
            pair.0.time.addingTimeInterval(300)
        )
    }

    // MARK: - Position

    func testCompassDirectionWrapsAtTheNorthBoundary() {
        XCTAssertEqual(HorizontalCoordinates.compassDirection(forAzimuth: 348.75), "N")
        XCTAssertEqual(HorizontalCoordinates.compassDirection(forAzimuth: 337.4), "NW")
        XCTAssertEqual(HorizontalCoordinates.compassDirection(forAzimuth: 0), "N")
        XCTAssertEqual(HorizontalCoordinates.compassDirection(forAzimuth: 22.5), "NE")
        XCTAssertEqual(HorizontalCoordinates.compassDirection(forAzimuth: 359.999), "N")
    }

    func testAzimuthIsNormalizedAndRightAscensionWrapsBy24Hours() {
        let time = date("2026-09-06T03:00:00Z")
        let base = HorizontalCoordinates.position(
            rightAscensionHours: 1.5, declinationDegrees: 20,
            latitudeDegrees: 40, longitudeDegrees: -74, at: time
        )
        let wrapped = HorizontalCoordinates.position(
            rightAscensionHours: 25.5, declinationDegrees: 20,
            latitudeDegrees: 40, longitudeDegrees: -74, at: time
        )
        XCTAssertEqual(base.altitude, wrapped.altitude, accuracy: 1e-9)
        XCTAssertEqual(base.azimuth, wrapped.azimuth, accuracy: 1e-9)
        XCTAssertTrue((0..<360).contains(base.azimuth))
    }

    func testLongitudeIsEastPositive() {
        let time = date("2026-09-06T03:00:00Z")
        let east = HorizontalCoordinates.position(
            rightAscensionHours: 0, declinationDegrees: 0,
            latitudeDegrees: 0, longitudeDegrees: 15, at: time
        )
        let shiftedHour = HorizontalCoordinates.position(
            rightAscensionHours: -1, declinationDegrees: 0,
            latitudeDegrees: 0, longitudeDegrees: 0, at: time
        )
        // Longitude is east-positive: +15 degrees raises the local hour angle by
        // 15 degrees, exactly as subtracting one hour of right ascension does.
        XCTAssertEqual(east.altitude, shiftedHour.altitude, accuracy: 1e-9)
    }

    // MARK: - Supported instant range

    func testTransportAcceptsTheInclusiveRangeBoundsAndRejectsJustOutside() throws {
        func position(_ time: String) throws -> [String: Any] {
            try DeepSkyObservationContract.evaluate(
                "astronomy.horizontal_position",
                input: [
                    "right_ascension": 16.6949, "declination": 36.4613,
                    "latitude": 40.7, "longitude": -74.0, "time": time,
                ],
                catalog: []
            )
        }
        XCTAssertNoThrow(try position("2000-01-01T00:00:00Z"))
        XCTAssertNoThrow(try position("2499-12-31T23:59:59Z"))
        XCTAssertThrowsError(try position("1999-12-31T23:59:59Z"))
        XCTAssertThrowsError(try position("2500-01-01T00:00:00Z"))
    }

    func testWindowTransportEnforcesTheRangeOnEachTimestampField() {
        func windows(_ start: String, _ end: String) throws -> [String: Any] {
            try DeepSkyObservationContract.evaluate(
                "targets.deep_sky_windows",
                input: [
                    "right_ascension": 16.6949, "declination": 36.4613,
                    "latitude": 40.7, "longitude": -74.0,
                    "night_start": start, "night_end": end,
                ],
                catalog: []
            )
        }
        XCTAssertNoThrow(try windows("2000-01-01T00:00:00Z", "2000-01-01T08:00:00Z"))
        XCTAssertNoThrow(try windows("2499-12-31T16:00:00Z", "2499-12-31T23:59:59Z"))
        XCTAssertThrowsError(try windows("1999-12-31T23:59:59Z", "2000-01-01T08:00:00Z"))
        XCTAssertThrowsError(try windows("2499-12-31T16:00:00Z", "2500-01-01T00:00:00Z"))
    }

    // MARK: - Sampling work cap

    func testSampleCapPreflightBoundaries() {
        let start = date("2026-01-01T00:00:00Z")
        // floor(span / 900) + 1 == 10080 exactly.
        let atLimit = start.addingTimeInterval(10_079 * 900)
        XCTAssertFalse(DeepSkyObservationContract.exceedsSampleCap(
            start: start, end: atLimit, sampleInterval: 900))
        XCTAssertTrue(DeepSkyObservationContract.exceedsSampleCap(
            start: start, end: atLimit.addingTimeInterval(900), sampleInterval: 900))
    }

    func testNonAdvancingStepExceedsTheCapEvenOnAZeroLengthInterval() {
        let start = date("2026-09-06T01:00:00Z")
        // The quotient is 0 here, so only the advance check can reject it.
        XCTAssertTrue(DeepSkyObservationContract.exceedsSampleCap(
            start: start, end: start, sampleInterval: 1e-9))
        XCTAssertTrue(DeepSkyObservationContract.exceedsSampleCap(
            start: start, end: start.addingTimeInterval(8 * 3600), sampleInterval: 1e-9))
    }

    func testAccumulationDriftCannotSlipPastTheCap() {
        // span/interval is only ~10079.1, so a mathematical count formula would
        // accept, but repeated addition realizes a slightly smaller step and emits
        // 10083 samples. The preflight must reject it.
        let start = date("2026-08-29T10:40:00Z")
        let end = start.addingTimeInterval(1)
        let interval = 9.921520770703732e-05
        XCTAssertLessThan(end.timeIntervalSince(start) / interval, Double(DeepSkyObservationContract.maxSampleCount))
        XCTAssertTrue(DeepSkyObservationContract.exceedsSampleCap(
            start: start, end: end, sampleInterval: interval))
        XCTAssertGreaterThan(
            loopIterations(start: start, end: end, interval: interval),
            DeepSkyObservationContract.maxSampleCount
        )
    }

    func testNoAcceptedRequestExceedsTheCapAcrossAdversarialIntervals() {
        // Drive intervals right at the cap boundary, where rounding drift matters,
        // at both ends of the supported timestamp range.
        // Fully seeded: no system randomness, so a failure is reproducible.
        var seed: UInt64 = 0x5DEECE66D
        func unitRandom() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 11) / Double(UInt64(1) << 53)
        }
        func next(_ lower: Double, _ upper: Double) -> Double {
            lower + unitRandom() * (upper - lower)
        }
        func nextIndex(_ count: Int) -> Int {
            min(Int(unitRandom() * Double(count)), count - 1)
        }
        let epochs = [
            DeepSkyObservationContract.earliestInstant,
            Date(timeIntervalSince1970: 1_788_000_000),
            DeepSkyObservationContract.latestInstant.addingTimeInterval(-100_000),
        ]
        var accepted = 0
        var worst = 0
        for epoch in epochs {
            for _ in 0..<400 {
                let spans = [0.0, 1.0, 60.0, 3600.0, next(0, 100_000)]
                let span = spans[nextIndex(spans.count)]
                let interval = span > 0
                    ? span / next(9_000, 11_000) * next(0.98, 1.02)
                    : next(1e-9, 1e-3)
                guard interval > 0, interval.isFinite else { continue }
                let end = epoch.addingTimeInterval(span)
                guard !DeepSkyObservationContract.exceedsSampleCap(
                    start: epoch, end: end, sampleInterval: interval) else { continue }
                accepted += 1
                let iterations = loopIterations(start: epoch, end: end, interval: interval)
                worst = max(worst, iterations)
                XCTAssertLessThanOrEqual(
                    iterations, DeepSkyObservationContract.maxSampleCount,
                    "span \(span) interval \(interval) at \(epoch)"
                )
            }
        }
        XCTAssertGreaterThan(accepted, 0)
        XCTAssertLessThanOrEqual(worst, DeepSkyObservationContract.maxSampleCount)
    }

    /// Replays the normative repeated-addition loop and counts iterations only.
    private func loopIterations(start: Date, end: Date, interval: TimeInterval) -> Int {
        var count = 0
        var time = start
        while time <= end {
            count += 1
            time = time.addingTimeInterval(interval)
            if count > 60_000 { return count }
        }
        return count
    }

    func testInvertedIntervalIsNotACap() {
        let start = date("2026-09-06T09:00:00Z")
        XCTAssertFalse(DeepSkyObservationContract.exceedsSampleCap(
            start: start, end: start.addingTimeInterval(-8 * 3600), sampleInterval: 1e-9))
    }

    func testSampleCapSurfacesItsOwnErrorCode() {
        do {
            _ = try DeepSkyObservationContract.evaluate(
                "targets.deep_sky_windows",
                input: [
                    "right_ascension": 16.6949, "declination": 36.4613,
                    "latitude": 40.7, "longitude": -74.0,
                    "night_start": "2026-09-06T01:00:00Z",
                    "night_end": "2026-09-06T09:00:00Z",
                    "sample_interval_seconds": 1e-9,
                ],
                catalog: []
            )
            XCTFail("expected a sample cap failure")
        } catch let error as DeepSkyObservationInputError {
            XCTAssertEqual(error.code, "sample_cap")
            XCTAssertEqual(error.message, "targets.deep_sky_windows exceeds the 1.0 sample cap (10080 samples)")
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testProductionCadencesAreWellInsideTheCap() {
        let start = date("2026-09-06T01:00:00Z")
        let night = start.addingTimeInterval(14 * 3600)
        for interval in [600.0, 900.0, 3600.0] {
            XCTAssertFalse(DeepSkyObservationContract.exceedsSampleCap(
                start: start, end: night, sampleInterval: interval), "interval \(interval)")
        }
    }

    func testTypedApiIsUnaffectedByTheTransportRange() {
        // The production Date API keeps working outside the wire range; only
        // transport parsing/formatting is bounded.
        let ancient = Date(timeIntervalSince1970: -62_135_769_600)
        let rows = DeepSkyObservation.samples(
            rightAscensionHours: 16.6949, declinationDegrees: 36.4613,
            latitudeDegrees: 40.7, longitudeDegrees: -74.0,
            start: ancient, end: ancient.addingTimeInterval(3600)
        )
        XCTAssertEqual(rows.count, 5)
    }

    func testAltitudeIsGeometricWithNoRefractionAtTheHorizon() {
        // A pole-on observer sees the celestial pole at exactly the latitude,
        // with no refraction lift near zero.
        let position = HorizontalCoordinates.position(
            rightAscensionHours: 6, declinationDegrees: 0,
            latitudeDegrees: 90, longitudeDegrees: 0, at: date("2026-09-06T03:00:00Z")
        )
        XCTAssertEqual(position.altitude, 0, accuracy: 1e-9)
    }

    func testZenithRoundingIsClampedInsteadOfReturningNaN() {
        // Observer latitude equals declination at a transit instant where the
        // unclamped spherical identity is 1 + 1 ULP. Darwin asin would return
        // NaN; the domain clamp keeps altitude at 90°.
        let position = HorizontalCoordinates.position(
            rightAscensionHours: 2, declinationDegrees: 34,
            latitudeDegrees: 34, longitudeDegrees: -74,
            at: Date(timeIntervalSince1970: 1_772_568_572.8249793)
        )
        XCTAssertTrue(position.altitude.isFinite)
        XCTAssertTrue(position.azimuth.isFinite)
        XCTAssertEqual(position.altitude, 90, accuracy: 1e-9)
    }
}

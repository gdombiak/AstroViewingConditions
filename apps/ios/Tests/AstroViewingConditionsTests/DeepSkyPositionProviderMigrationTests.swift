import AstroEngine
import SharedCode
import XCTest

/// Migration equivalence for the deep-sky observation slice.
///
/// `LegacyDeepSkyPositionOracle` is a verbatim copy of the pre-migration
/// `DeepSkyTargetPositionProvider` math (sampling, threshold, run construction,
/// crossing interpolation, compass direction). It exists only to prove that the
/// shared `AstroEngine.DeepSkyObservation` implementation reproduces the old
/// production behavior exactly across a broad input sweep.
final class DeepSkyPositionProviderMigrationTests: XCTestCase {
    private let catalog = CuratedDeepSkyCatalogProvider().entries()

    func testEngineMatchesLegacyImplementationAcrossBroadInputs() {
        let latitudes: [Double] = [-89, -66.5, -34, -12.3, 0, 19.7, 34, 51.5, 66.5, 78, 89]
        let longitudes: [Double] = [-179.5, -118, -74.006, -0.1276, 0, 37.6, 121.5, 179.5]
        let nightStarts: [Date] = [
            Date(timeIntervalSince1970: 1_772_500_000),  // 2026-03
            Date(timeIntervalSince1970: 1_788_000_000),  // 2026-09
            Date(timeIntervalSince1970: 1_609_459_200),  // 2021-01-01T00:00:00Z
            Date(timeIntervalSince1970: 946_684_800),    // 2000-01-01T00:00:00Z
        ]
        // Whole-multiple, non-divisible, zero-length, inverted and multi-day.
        let durations: [TimeInterval] = [0, -3600, 900, 3600, 8 * 3600, 8 * 3600 + 137, 30 * 3600]
        let settings: [(minimumAltitude: Double, sampleInterval: TimeInterval)] = [
            (15, 900), (40, 900), (-90, 900), (0, 900), (15, 600), (15, 3600), (89.9, 900),
        ]

        var comparisons = 0
        for setting in settings {
            let provider = DeepSkyTargetPositionProvider(
                minimumAltitude: setting.minimumAltitude,
                sampleInterval: setting.sampleInterval
            )
            for latitude in latitudes {
                for longitude in longitudes {
                    for start in nightStarts {
                        for duration in durations {
                            // Keep the sweep bounded: only exercise a slice of the
                            // catalog per geometry, rotating through every entry.
                            let entry = catalog[comparisons % catalog.count]
                            let context = makeContext(
                                latitude: latitude,
                                longitude: longitude,
                                start: start,
                                end: start.addingTimeInterval(duration)
                            )
                            let target = makeTarget(entry)
                            let actual = provider.visibilityWindows(for: target, context: context)
                            let expected = LegacyDeepSkyPositionOracle.visibilityWindows(
                                entry: entry,
                                context: context,
                                minimumAltitude: setting.minimumAltitude,
                                sampleInterval: setting.sampleInterval
                            )
                            comparisons += 1
                            guard actual.count == expected.count else {
                                XCTFail("window count \(actual.count) != \(expected.count) for \(entry.id) at \(latitude),\(longitude)")
                                continue
                            }
                            for (produced, legacy) in zip(actual, expected) {
                                XCTAssertEqual(produced.start, legacy.start)
                                XCTAssertEqual(produced.end, legacy.end)
                                XCTAssertEqual(produced.bestTime, legacy.bestTime)
                                XCTAssertEqual(produced.maxAltitude, legacy.maxAltitude)
                                XCTAssertEqual(produced.azimuth, legacy.azimuth)
                                XCTAssertEqual(produced.direction, legacy.direction)
                                XCTAssertEqual(produced.id, legacy.id)
                            }
                        }
                    }
                }
            }
        }
        XCTAssertEqual(comparisons, 7 * 11 * 8 * 4 * 7)
        print("[deep-sky migration] compared \(comparisons) provider invocations")
    }

    func testNonDeepSkyAndUnknownTargetsStillProduceNoWindows() {
        let context = makeContext(
            latitude: 34, longitude: -118,
            start: Date(timeIntervalSince1970: 1_788_000_000),
            end: Date(timeIntervalSince1970: 1_788_000_000 + 8 * 3600)
        )
        let provider = DeepSkyTargetPositionProvider()
        let planet = ObservableTarget(id: "jupiter", name: "Jupiter", type: .planet,
                                     preferredEquipment: .telescope, difficulty: 0.2,
                                     observingIntent: .easy)
        XCTAssertTrue(provider.visibilityWindows(for: planet, context: context).isEmpty)

        let unknown = ObservableTarget(id: "not-in-catalog", name: "Unknown", type: .deepSky,
                                       preferredEquipment: .telescope, difficulty: 0.2,
                                       observingIntent: .easy)
        XCTAssertTrue(provider.visibilityWindows(for: unknown, context: context).isEmpty)
    }

    // MARK: - Helpers

    private func makeTarget(_ entry: DeepSkyCatalogEntry) -> ObservableTarget {
        ObservableTarget(
            id: entry.id,
            name: entry.commonName,
            type: .deepSky,
            preferredEquipment: entry.recommendedEquipment,
            difficulty: entry.difficulty,
            observingIntent: entry.observingIntent,
            deepSkyObjectType: entry.objectType
        )
    }

    private func makeContext(
        latitude: Double,
        longitude: Double,
        start: Date,
        end: Date
    ) -> TargetRecommendationContext {
        TargetRecommendationContext(
            location: CachedLocation(name: "Sweep", latitude: latitude, longitude: longitude, elevation: 0),
            astronomicalNightStart: start,
            astronomicalNightEnd: end,
            nightQuality: NightQualityAssessment(
                rating: .good,
                summary: "Sweep",
                details: NightQualityAssessment.Details(
                    cloudCoverScore: 5, fogScoreAvg: 5, moonIlluminationAvg: 0, windSpeedAvg: 2
                ),
                bestWindow: nil,
                hourlyRatings: [],
                nightStart: start,
                nightEnd: end
            ),
            moonInfo: MoonInfo(phase: 0, phaseName: "New Moon", altitude: -10, illumination: 0, emoji: "🌑")
        )
    }
}

/// Verbatim pre-migration production math. Do not "improve" it: its only job is
/// to be the old behavior.
private enum LegacyDeepSkyPositionOracle {
    static func visibilityWindows(
        entry: DeepSkyCatalogEntry,
        context: TargetRecommendationContext,
        minimumAltitude: Double,
        sampleInterval: TimeInterval
    ) -> [TargetVisibilityWindow] {
        let samples = sampledPositions(
            for: entry, context: context, sampleInterval: sampleInterval
        )
        var windows: [TargetVisibilityWindow] = []
        var runStartIndex: Int?

        for index in samples.indices {
            let isVisible = samples[index].altitude >= minimumAltitude
            if isVisible, runStartIndex == nil {
                runStartIndex = index
            }

            let runEnded = runStartIndex != nil && (!isVisible || index == samples.index(before: samples.endIndex))
            guard runEnded, let startIndex = runStartIndex else { continue }

            let endIndex = isVisible ? index : samples.index(before: index)
            let run = samples[startIndex...endIndex]
            guard let best = run.max(by: { $0.altitude < $1.altitude }) else { continue }

            let start = startIndex == samples.startIndex
                ? context.astronomicalNightStart
                : thresholdCrossing(between: samples[startIndex - 1], and: samples[startIndex], minimumAltitude: minimumAltitude)
            let end = endIndex == samples.index(before: samples.endIndex)
                ? context.astronomicalNightEnd
                : thresholdCrossing(between: samples[endIndex], and: samples[endIndex + 1], minimumAltitude: minimumAltitude)

            windows.append(TargetVisibilityWindow(
                start: start,
                end: end,
                bestTime: best.date,
                maxAltitude: best.altitude,
                direction: compassDirection(for: best.azimuth),
                azimuth: best.azimuth
            ))
            runStartIndex = nil
        }

        return windows
    }

    private static func thresholdCrossing(
        between first: HorizontalPosition,
        and second: HorizontalPosition,
        minimumAltitude: Double
    ) -> Date {
        let altitudeChange = second.altitude - first.altitude
        guard abs(altitudeChange) > 0.0001 else { return first.date }
        let fraction = min(max((minimumAltitude - first.altitude) / altitudeChange, 0), 1)
        return first.date.addingTimeInterval(second.date.timeIntervalSince(first.date) * fraction)
    }

    private static func sampledPositions(
        for entry: DeepSkyCatalogEntry,
        context: TargetRecommendationContext,
        sampleInterval: TimeInterval
    ) -> [HorizontalPosition] {
        var positions: [HorizontalPosition] = []
        var date = context.astronomicalNightStart
        while date <= context.astronomicalNightEnd {
            positions.append(horizontalPosition(
                rightAscensionHours: entry.rightAscension,
                declinationDegrees: entry.declination,
                date: date,
                latitudeDegrees: context.location.latitude,
                longitudeDegrees: context.location.longitude
            ))
            date = date.addingTimeInterval(sampleInterval)
        }
        return positions
    }

    private static func horizontalPosition(
        rightAscensionHours: Double,
        declinationDegrees: Double,
        date: Date,
        latitudeDegrees: Double,
        longitudeDegrees: Double
    ) -> HorizontalPosition {
        let julianDate = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let daysSinceJ2000 = julianDate - 2_451_545.0
        let greenwichSiderealDegrees = normalizedDegrees(280.46061837 + 360.98564736629 * daysSinceJ2000)
        let localSiderealDegrees = normalizedDegrees(greenwichSiderealDegrees + longitudeDegrees)
        let hourAngle = normalizedSignedDegrees(localSiderealDegrees - rightAscensionHours * 15).legacyRadians
        let declination = declinationDegrees.legacyRadians
        let latitude = latitudeDegrees.legacyRadians

        let altitude = asin(
            sin(declination) * sin(latitude)
                + cos(declination) * cos(latitude) * cos(hourAngle)
        )
        let azimuth = atan2(
            sin(hourAngle),
            cos(hourAngle) * sin(latitude) - tan(declination) * cos(latitude)
        ) + .pi

        return HorizontalPosition(
            date: date,
            altitude: altitude.legacyDegrees,
            azimuth: normalizedDegrees(azimuth.legacyDegrees)
        )
    }

    private static func compassDirection(for azimuth: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return directions[Int((normalizedDegrees(azimuth) + 22.5) / 45) % directions.count]
    }

    private static func normalizedDegrees(_ value: Double) -> Double {
        let result = value.truncatingRemainder(dividingBy: 360)
        return result >= 0 ? result : result + 360
    }

    private static func normalizedSignedDegrees(_ value: Double) -> Double {
        let normalized = normalizedDegrees(value)
        return normalized > 180 ? normalized - 360 : normalized
    }

    struct HorizontalPosition {
        let date: Date
        let altitude: Double
        let azimuth: Double
    }
}

private extension Double {
    var legacyRadians: Double { self * .pi / 180 }
    var legacyDegrees: Double { self * 180 / .pi }
}

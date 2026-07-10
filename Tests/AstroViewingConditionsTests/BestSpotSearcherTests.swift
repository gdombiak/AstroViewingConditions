import SharedCode
import XCTest
import Foundation
@testable import AstroViewingConditions

final class BestSpotSearcherTests: XCTestCase {
    private struct MockWeatherProvider: WeatherForecastProviding {
        let forecasts: @Sendable (Coordinate) -> [HourlyForecast]

        func fetchForecastForMultipleLocations(
            coordinates: [Coordinate],
            days: Int
        ) async throws -> [Coordinate: [HourlyForecast]] {
            Dictionary(uniqueKeysWithValues: coordinates.map { ($0, forecasts($0)) })
        }
    }

    private actor MockAstronomyProvider: AstronomyProviding {
        func calculateSunEvents(latitude: Double, longitude: Double, on date: Date) async -> SunEvents {
            let calendar = Calendar(identifier: .gregorian)
            let start = calendar.startOfDay(for: date)
            return SunEvents(
                sunrise: start.addingTimeInterval(6 * 3600),
                sunset: start.addingTimeInterval(18 * 3600),
                civilTwilightBegin: start.addingTimeInterval(5 * 3600),
                civilTwilightEnd: start.addingTimeInterval(19 * 3600),
                nauticalTwilightBegin: start.addingTimeInterval(4.5 * 3600),
                nauticalTwilightEnd: start.addingTimeInterval(19.5 * 3600),
                astronomicalTwilightBegin: start.addingTimeInterval(4 * 3600),
                astronomicalTwilightEnd: start.addingTimeInterval(20 * 3600)
            )
        }

        func calculateMoonInfo(latitude: Double, longitude: Double, on date: Date) async -> MoonInfo {
            MoonInfo(phase: 0, phaseName: "New Moon", altitude: -10, illumination: 0, emoji: "New")
        }
    }

    private struct MockSuitabilityProvider: LocationSuitabilityProviding {
        let suitability: @Sendable (GridPoint) -> LocationSuitabilityStatus

        func suitability(for point: GridPoint) async -> LocationSuitabilityStatus {
            suitability(point)
        }

        func suitability(for points: [GridPoint]) async -> [GridPoint: LocationSuitabilityStatus] {
            Dictionary(uniqueKeysWithValues: points.map { ($0, suitability($0)) })
        }
    }

    private struct ReversedBatchSuitabilityProvider: LocationSuitabilityProviding {
        func suitability(for point: GridPoint) async -> LocationSuitabilityStatus {
            .suitable
        }

        func suitability(for points: [GridPoint]) async -> [GridPoint: LocationSuitabilityStatus] {
            Dictionary(uniqueKeysWithValues: points.reversed().map { ($0, LocationSuitabilityStatus.suitable) })
        }
    }

    private actor CountingSuitabilityProvider: LocationSuitabilityProviding {
        private let suitability: @Sendable (GridPoint) -> LocationSuitabilityStatus
        private(set) var checkedPoints: [GridPoint] = []

        init(suitability: @escaping @Sendable (GridPoint) -> LocationSuitabilityStatus) {
            self.suitability = suitability
        }

        func suitability(for point: GridPoint) async -> LocationSuitabilityStatus {
            checkedPoints.append(point)
            return suitability(point)
        }

        func suitability(for points: [GridPoint]) async -> [GridPoint: LocationSuitabilityStatus] {
            checkedPoints.append(contentsOf: points)
            return Dictionary(uniqueKeysWithValues: points.map { ($0, suitability($0)) })
        }

        var callCount: Int {
            checkedPoints.count
        }
    }

    private actor OrderedSuitabilityProvider: LocationSuitabilityProviding {
        private let suitability: @Sendable (Int, GridPoint) -> LocationSuitabilityStatus
        private(set) var checkedPoints: [GridPoint] = []

        init(suitability: @escaping @Sendable (Int, GridPoint) -> LocationSuitabilityStatus) {
            self.suitability = suitability
        }

        func suitability(for point: GridPoint) async -> LocationSuitabilityStatus {
            let index = checkedPoints.count
            checkedPoints.append(point)
            return suitability(index, point)
        }

        func suitability(for points: [GridPoint]) async -> [GridPoint: LocationSuitabilityStatus] {
            var results: [GridPoint: LocationSuitabilityStatus] = [:]

            for point in points {
                let index = checkedPoints.count
                checkedPoints.append(point)
                results[point] = suitability(index, point)
            }

            return results
        }

        var callCount: Int {
            checkedPoints.count
        }
    }

    private actor MockSuitabilityResolver: LocationSuitabilityResolving {
        private let resolver: @Sendable (Coordinate) -> LocationSuitabilityStatus
        private(set) var resolvedCoordinates: [Coordinate] = []

        init(resolver: @escaping @Sendable (Coordinate) -> LocationSuitabilityStatus) {
            self.resolver = resolver
        }

        func resolveSuitability(for coordinate: Coordinate) async -> LocationSuitabilityStatus {
            resolvedCoordinates.append(coordinate)
            return resolver(coordinate)
        }

        var callCount: Int {
            resolvedCoordinates.count
        }
    }

    private actor SearchScopedResolver: LocationSuitabilityResolving {
        private let unsuitableCallCount: Int
        private(set) var callCount = 0

        init(unsuitableCallCount: Int) {
            self.unsuitableCallCount = unsuitableCallCount
        }

        func resolveSuitability(for coordinate: Coordinate) async -> LocationSuitabilityStatus {
            callCount += 1
            return callCount <= unsuitableCallCount ? .unsuitable(reason: "Water area") : .suitable
        }
    }

    private struct MockBestSpotSearching: BestSpotSearching {
        let error: Error

        func findBestSpots(
            around center: CachedLocation,
            radiusMiles: Double,
            spacingMiles: Double,
            for date: Date,
            topN: Int,
            progressHandler: (@Sendable (Double) -> Void)?
        ) async throws -> BestSpotResult {
            throw error
        }
    }
    
    // MARK: - Helper Methods
    
    private func createDate(hour: Int, dayOffset: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 1 + dayOffset
        components.hour = hour
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar.current.date(from: components) ?? Date()
    }
    
    private func createSavedLocation(name: String = "Test Location") -> SavedLocation {
        SavedLocation(
            name: name,
            latitude: 40.7128,
            longitude: -74.0060
        )
    }
    
    private func createHourlyForecast(hour: Int, cloudCover: Int, humidity: Int, windSpeed: Double, dayOffset: Int = 0) -> HourlyForecast {
        HourlyForecast(
            time: createDate(hour: hour, dayOffset: dayOffset),
            cloudCover: cloudCover,
            humidity: humidity,
            windSpeed: windSpeed,
            windDirection: 180,
            temperature: 15.0,
            dewPoint: 5.0,
            visibility: 20000,
            lowCloudCover: nil
        )
    }

    private func currentSearchDate() -> Date {
        Calendar(identifier: .gregorian).startOfDay(for: Date())
    }

    private static func nightForecasts(
        for date: Date,
        cloudCover: Int,
        humidity: Int = 40,
        windSpeed: Double = 4
    ) -> [HourlyForecast] {
        let start = Calendar(identifier: .gregorian).startOfDay(for: date)
        return [20, 21, 22, 23].map { hour in
            HourlyForecast(
                time: start.addingTimeInterval(Double(hour) * 3600),
                cloudCover: cloudCover,
                humidity: humidity,
                windSpeed: windSpeed,
                windDirection: 180,
                temperature: 12,
                dewPoint: 4,
                visibility: 20_000,
                lowCloudCover: nil
            )
        }
    }

    private static func testNightQuality(rating: NightQualityAssessment.Rating = .good) -> NightQualityAssessment {
        NightQualityAssessment(
            rating: rating,
            summary: "Good conditions for viewing",
            details: NightQualityAssessment.Details(
                cloudCoverScore: 20.0,
                fogScoreAvg: 10.0,
                moonIlluminationAvg: 25,
                windSpeedAvg: 5.0
            ),
            bestWindow: nil,
            hourlyRatings: [],
            nightStart: Date(),
            nightEnd: Date().addingTimeInterval(3600 * 8)
        )
    }

    private func searcher(
        weather: MockWeatherProvider,
        suitability: any LocationSuitabilityProviding = MockSuitabilityProvider { _ in .unknown(reason: .notChecked) },
        fogScoreCalculator: @escaping @Sendable (HourlyForecast) -> FogScore = FogCalculator.calculate
    ) -> BestSpotSearcher {
        BestSpotSearcher(
            weatherService: weather,
            astronomyService: MockAstronomyProvider(),
            suitabilityService: suitability,
            fogScoreCalculator: fogScoreCalculator
        )
    }
    
    // MARK: - BestSpotSearchError Tests
    
    func testNoLocationsFoundError() {
        let error = BestSpotSearchError.noLocationsFound
        XCTAssertEqual(error.errorDescription, "No locations found in the search area.")
    }
    
    func testNoWeatherDataError() {
        let error = BestSpotSearchError.noWeatherData
        XCTAssertEqual(error.errorDescription, "Unable to retrieve weather data for the search area.")
    }
    
    func testInvalidDateError() {
        let error = BestSpotSearchError.invalidDate
        XCTAssertEqual(error.errorDescription, "Invalid search date.")
    }

    func testUnsupportedForecastDateErrorIsHelpful() {
        let error = BestSpotSearchError.unsupportedForecastDate(maxDays: 16)
        XCTAssertEqual(error.errorDescription, "Forecasts are only available for the next 16 days. Choose a nearer night.")
    }

    func testNoScorableLocationsErrorIsHelpful() {
        let error = BestSpotSearchError.noScorableLocations
        XCTAssertEqual(error.errorDescription, "Weather data was available, but no night conditions could be scored for the selected date.")
    }

    func testNoRecommendableLocationsErrorIsHelpful() {
        let error = BestSpotSearchError.noRecommendableLocations
        XCTAssertEqual(error.errorDescription, "No recommendable nearby areas found. The best-scoring candidates appear to be water or could not be verified. Try a different starting location, search radius, or date.")
    }
    
    // MARK: - Grid Generation Integration Tests
    
    func testGenerateGridWithDefaultParameters() {
        let center = Coordinate(latitude: 40.7128, longitude: -74.0060)
        let grid = GeographicGridGenerator.generateGrid(
            around: center,
            radiusMiles: 30,
            spacingMiles: 5
        )
        
        // Center + 6 rings
        // Should have many points (center + rings)
        XCTAssertGreaterThan(grid.count, 30)
        XCTAssertLessThan(grid.count, 150)
        
        // First point should be center
        XCTAssertEqual(grid[0].coordinate.latitude, center.latitude, accuracy: 0.0001)
        XCTAssertEqual(grid[0].coordinate.longitude, center.longitude, accuracy: 0.0001)
    }

    func testFutureDateBeyondSupportedForecastRangeThrowsSpecificError() async throws {
        let date = Calendar(identifier: .gregorian).date(
            byAdding: .day,
            value: BestSpotSearcher.maxForecastDays + 5,
            to: currentSearchDate()
        )!
        let searcher = searcher(weather: MockWeatherProvider { _ in [] })

        do {
            _ = try await searcher.findBestSpots(
                around: CachedLocation(from: createSavedLocation()),
                radiusMiles: 10,
                spacingMiles: 10,
                for: date,
                topN: 5
            )
            XCTFail("Expected unsupported forecast date")
        } catch BestSpotSearchError.unsupportedForecastDate(let maxDays) {
            XCTAssertEqual(maxDays, BestSpotSearcher.maxForecastDays)
        }
    }

    func testWeatherDataWithoutNightForecastsThrowsNoScorableLocations() async throws {
        let date = currentSearchDate()
        let start = Calendar(identifier: .gregorian).startOfDay(for: date)
        let daytimeForecasts = [
            HourlyForecast(
                time: start.addingTimeInterval(12 * 3600),
                cloudCover: 5,
                humidity: 40,
                windSpeed: 4,
                windDirection: 180,
                temperature: 15,
                dewPoint: 4,
                visibility: 20_000,
                lowCloudCover: nil
            )
        ]
        let searcher = searcher(weather: MockWeatherProvider { _ in daytimeForecasts })

        do {
            _ = try await searcher.findBestSpots(
                around: CachedLocation(from: createSavedLocation()),
                radiusMiles: 10,
                spacingMiles: 10,
                for: date,
                topN: 5
            )
            XCTFail("Expected no scorable locations")
        } catch BestSpotSearchError.noScorableLocations {
            XCTAssertTrue(true)
        }
    }

    func testAverageFogIsComputedAcrossNightWindow() async throws {
        let date = currentSearchDate()
        let forecasts = Self.nightForecasts(for: date, cloudCover: 5)
        let searcher = searcher(
            weather: MockWeatherProvider { _ in forecasts },
            fogScoreCalculator: { forecast in
                Calendar(identifier: .gregorian).component(.hour, from: forecast.time) == 20
                    ? FogScore(score: 80, factors: [.highHumidity])
                    : FogScore(score: 20, factors: [.lowWind])
            }
        )

        let result = try await searcher.findBestSpots(
            around: CachedLocation(from: createSavedLocation()),
            radiusMiles: 10,
            spacingMiles: 10,
            for: date,
            topN: 5
        )

        XCTAssertEqual(result.bestSpot?.fogScore.score, 35)
        XCTAssertEqual(Set(result.bestSpot?.fogScore.factors ?? []), Set([.highHumidity, .lowWind]))
    }

    func testWaterCoordinateExcludedFromTopRecommendations() async throws {
        let date = currentSearchDate()
        let searcher = searcher(
            weather: MockWeatherProvider { coordinate in
                let isCenter = abs(coordinate.latitude - 40.7128) < 0.0001 && abs(coordinate.longitude + 74.0060) < 0.0001
                return Self.nightForecasts(for: date, cloudCover: isCenter ? 80 : 1)
            },
            suitability: MockSuitabilityProvider { point in
                point.distanceMiles == 0 ? .suitable : .unsuitable(reason: "Water area")
            }
        )

        let result = try await searcher.findBestSpots(
            around: CachedLocation(from: createSavedLocation()),
            radiusMiles: 10,
            spacingMiles: 10,
            for: date,
            topN: 5
        )

        XCTAssertEqual(result.topLocations.count, 1)
        XCTAssertEqual(result.bestSpot?.point.distanceMiles, 0)
        XCTAssertTrue(result.topLocations.allSatisfy { $0.suitability.isRecommendable })
        XCTAssertFalse(result.topLocations.contains { $0.suitability == .unsuitable(reason: "Water area") })
    }

    func testSuitabilityIsNotCheckedForEveryScoredPoint() async throws {
        let date = currentSearchDate()
        let suitability = CountingSuitabilityProvider { _ in .suitable }
        let searcher = searcher(
            weather: MockWeatherProvider { _ in
                Self.nightForecasts(for: date, cloudCover: 5)
            },
            suitability: suitability
        )

        let result = try await searcher.findBestSpots(
            around: CachedLocation(from: createSavedLocation()),
            radiusMiles: 30,
            spacingMiles: 5,
            for: date,
            topN: 5
        )

        let callCount = await suitability.callCount
        XCTAssertGreaterThan(result.allScoredLocations.count, callCount)
        XCTAssertEqual(callCount, BestSpotSearcher.suitabilityCandidateCount(topN: 5))
    }

    func testSuitabilityIsCheckedOnlyForBoundedTopCandidatePool() async throws {
        let date = currentSearchDate()
        let suitability = CountingSuitabilityProvider { _ in .suitable }
        let searcher = searcher(
            weather: MockWeatherProvider { _ in
                Self.nightForecasts(for: date, cloudCover: 5)
            },
            suitability: suitability
        )

        let result = try await searcher.findBestSpots(
            around: CachedLocation(from: createSavedLocation()),
            radiusMiles: 30,
            spacingMiles: 10,
            for: date,
            topN: 5
        )

        let candidateCount = BestSpotSearcher.suitabilityCandidateCount(topN: 5)
        let expectedCoordinates = Set(result.allScoredLocations.prefix(candidateCount).map(\.point.coordinate))
        let uncheckedAfterPool = result.allScoredLocations.dropFirst(candidateCount)
        let checkedCoordinates = Set(await suitability.checkedPoints.map(\.coordinate))

        XCTAssertEqual(checkedCoordinates, expectedCoordinates)
        XCTAssertTrue(uncheckedAfterPool.allSatisfy { $0.suitability == LocationSuitabilityStatus.unchecked })
    }

    func testBestWeatherWaterCandidateFallsBackToNextSuitableCandidate() async throws {
        let date = currentSearchDate()
        let searcher = searcher(
            weather: MockWeatherProvider { _ in
                Self.nightForecasts(for: date, cloudCover: 5)
            },
            suitability: MockSuitabilityProvider { point in
                point.isCenter ? .unsuitable(reason: "Water area") : .suitable
            }
        )

        let result = try await searcher.findBestSpots(
            around: CachedLocation(from: createSavedLocation()),
            radiusMiles: 10,
            spacingMiles: 10,
            for: date,
            topN: 5
        )

        XCTAssertFalse(result.bestSpot?.point.isCenter ?? true)
        XCTAssertEqual(result.bestSpot?.suitability, .suitable)
    }

    func testAllWaterSearchStopsAtSuitabilityCapAndThrowsNoRecommendableLocations() async throws {
        let date = currentSearchDate()
        let suitability = CountingSuitabilityProvider { _ in .unsuitable(reason: "Water area") }
        let searcher = searcher(
            weather: MockWeatherProvider { _ in
                Self.nightForecasts(for: date, cloudCover: 5)
            },
            suitability: suitability
        )
        let expectedScoredCount = GeographicGridGenerator.generateGrid(
            around: Coordinate(latitude: 40.7128, longitude: -74.0060),
            radiusMiles: 50,
            spacingMiles: 5
        ).count
        XCTAssertGreaterThan(expectedScoredCount, BestSpotSearcher.maxSuitabilityCandidateChecks)

        do {
            _ = try await searcher.findBestSpots(
                around: CachedLocation(from: createSavedLocation()),
                radiusMiles: 50,
                spacingMiles: 5,
                for: date,
                topN: 5
            )
            XCTFail("Expected no recommendable locations")
        } catch BestSpotSearchError.noRecommendableLocations {
            XCTAssertTrue(true)
        }

        let callCount = await suitability.callCount
        XCTAssertLessThanOrEqual(callCount, BestSpotSearcher.maxSuitabilityCandidateChecks)
        XCTAssertEqual(callCount, BestSpotSearcher.maxSuitabilityCandidateChecks)
        XCTAssertLessThan(callCount, expectedScoredCount)
    }

    func testPartialRecommendationsReturnBeforeEnoughTopCandidatesFound() async throws {
        let date = currentSearchDate()
        let suitability = OrderedSuitabilityProvider { index, _ in
            index == 0 ? .suitable : .unsuitable(reason: "Water area")
        }
        let searcher = searcher(
            weather: MockWeatherProvider { _ in
                Self.nightForecasts(for: date, cloudCover: 5)
            },
            suitability: suitability
        )

        let result = try await searcher.findBestSpots(
            around: CachedLocation(from: createSavedLocation()),
            radiusMiles: 50,
            spacingMiles: 5,
            for: date,
            topN: 5
        )

        let callCount = await suitability.callCount
        XCTAssertEqual(result.topLocations.count, 1)
        XCTAssertEqual(result.bestSpot?.suitability, .suitable)
        XCTAssertEqual(callCount, BestSpotSearcher.maxSuitabilityCandidateChecks)
    }

    func testCandidatePoolExpandsWhenFirstBandIsWaterAndNextCandidateIsSuitable() async throws {
        let date = currentSearchDate()
        let suitability = OrderedSuitabilityProvider { index, _ in
            index < BestSpotSearcher.suitabilityCandidateCount(topN: 1)
                ? .unsuitable(reason: "Water area")
                : .suitable
        }
        let searcher = searcher(
            weather: MockWeatherProvider { _ in
                Self.nightForecasts(for: date, cloudCover: 5)
            },
            suitability: suitability
        )

        let result = try await searcher.findBestSpots(
            around: CachedLocation(from: createSavedLocation()),
            radiusMiles: 50,
            spacingMiles: 10,
            for: date,
            topN: 1
        )

        XCTAssertEqual(result.bestSpot?.suitability, .suitable)
        let callCount = await suitability.callCount
        XCTAssertGreaterThan(callCount, BestSpotSearcher.suitabilityCandidateCount(topN: 1))
    }

    func testSecondCandidateBandFillsMissingRecommendations() async throws {
        let date = currentSearchDate()
        let firstBandSize = BestSpotSearcher.suitabilityCandidateCount(topN: 5)
        let suitability = OrderedSuitabilityProvider { index, _ in
            if index < 3 { return .suitable }
            if index < firstBandSize { return .unsuitable(reason: "Water area") }
            return .suitable
        }
        let searcher = searcher(
            weather: MockWeatherProvider { _ in
                Self.nightForecasts(for: date, cloudCover: 5)
            },
            suitability: suitability
        )

        let result = try await searcher.findBestSpots(
            around: CachedLocation(from: createSavedLocation()),
            radiusMiles: 50,
            spacingMiles: 10,
            for: date,
            topN: 5
        )

        XCTAssertEqual(result.topLocations.count, 5)
        let callCount = await suitability.callCount
        XCTAssertEqual(callCount, firstBandSize * 2)
        XCTAssertTrue(result.topLocations.allSatisfy { $0.suitability.isRecommendable })
    }

    func testExpansionStopsAfterFirstBandWhenEnoughRecommendationsFound() async throws {
        let date = currentSearchDate()
        let suitability = CountingSuitabilityProvider { _ in .suitable }
        let searcher = searcher(
            weather: MockWeatherProvider { _ in
                Self.nightForecasts(for: date, cloudCover: 5)
            },
            suitability: suitability
        )

        let result = try await searcher.findBestSpots(
            around: CachedLocation(from: createSavedLocation()),
            radiusMiles: 50,
            spacingMiles: 10,
            for: date,
            topN: 5
        )

        XCTAssertEqual(result.topLocations.count, 5)
        let callCount = await suitability.callCount
        XCTAssertEqual(callCount, BestSpotSearcher.suitabilityCandidateCount(topN: 5))
    }

    func testExpansionDoesNotRecheckAlreadyCheckedCandidates() async throws {
        let date = currentSearchDate()
        let firstBandSize = BestSpotSearcher.suitabilityCandidateCount(topN: 5)
        let suitability = OrderedSuitabilityProvider { index, _ in
            index < firstBandSize ? .unsuitable(reason: "Water area") : .suitable
        }
        let searcher = searcher(
            weather: MockWeatherProvider { _ in
                Self.nightForecasts(for: date, cloudCover: 5)
            },
            suitability: suitability
        )

        _ = try await searcher.findBestSpots(
            around: CachedLocation(from: createSavedLocation()),
            radiusMiles: 50,
            spacingMiles: 10,
            for: date,
            topN: 5
        )

        let checkedPoints = await suitability.checkedPoints
        XCTAssertEqual(checkedPoints.count, Set(checkedPoints).count)
    }

    func testUnknownSuitabilityDoesNotClaimVerifiedAccess() async throws {
        let date = currentSearchDate()
        let searcher = searcher(weather: MockWeatherProvider { _ in
            Self.nightForecasts(for: date, cloudCover: 5)
        })

        let result = try await searcher.findBestSpots(
            around: CachedLocation(from: createSavedLocation()),
            radiusMiles: 10,
            spacingMiles: 10,
            for: date,
            topN: 5
        )

        XCTAssertEqual(result.bestSpot?.suitability, .unknown(reason: .notChecked))
        XCTAssertEqual(result.bestSpot?.suitability.label, "Access not verified")
    }

    func testGeocoderFailureProducesDistinctUnknownState() async throws {
        let resolver = MockSuitabilityResolver { _ in .unknown(reason: .geocodingFailed) }
        let service = LocationSuitabilityService(resolver: resolver)

        let status = await service.suitability(for: GridPoint(
            coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
            distanceMiles: 0,
            bearing: 0,
            isCenter: true
        ))

        XCTAssertEqual(status, .unknown(reason: .geocodingFailed))
        XCTAssertEqual(status.label, "Verification unavailable")
    }

    func testRateLimitLikeFailureProducesTemporarilyUnavailableState() async throws {
        let resolver = MockSuitabilityResolver { _ in .unknown(reason: .temporarilyUnavailable) }
        let service = LocationSuitabilityService(resolver: resolver)

        let status = await service.suitability(for: GridPoint(
            coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
            distanceMiles: 0,
            bearing: 0,
            isCenter: true
        ))

        XCTAssertEqual(status, .unknown(reason: .temporarilyUnavailable))
        XCTAssertEqual(status.label, "Verification temporarily unavailable")
    }

    func testGeocoderThrottleErrorProducesTemporarilyUnavailableState() {
        let error = NSError(domain: "GEOErrorDomain", code: -3)

        let status = CoreLocationSuitabilityResolver.suitabilityStatus(for: error)

        XCTAssertEqual(status, .unknown(reason: .temporarilyUnavailable))
    }

    func testRepeatedCoordinatesUseOneSearchSessionCache() async throws {
        let resolver = MockSuitabilityResolver { _ in .suitable }
        let service = LocationSuitabilityService(resolver: resolver)
        let session = service.makeSearchSession()
        let point = GridPoint(
            coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
            distanceMiles: 0,
            bearing: 0,
            isCenter: true
        )

        _ = await session.suitability(for: point)
        _ = await session.suitability(for: point)

        let callCount = await resolver.callCount
        XCTAssertEqual(callCount, 1)
    }

    func testNearbyCoordinatesThatRoundToSameKeyShareOneSearchSessionCache() async throws {
        let resolver = MockSuitabilityResolver { _ in .suitable }
        let service = LocationSuitabilityService(resolver: resolver)
        let session = service.makeSearchSession()

        _ = await session.suitability(for: GridPoint(
            coordinate: Coordinate(latitude: 40.71281, longitude: -74.00601),
            distanceMiles: 0,
            bearing: 0
        ))
        _ = await session.suitability(for: GridPoint(
            coordinate: Coordinate(latitude: 40.71284, longitude: -74.00604),
            distanceMiles: 0,
            bearing: 0
        ))

        let callCount = await resolver.callCount
        XCTAssertEqual(callCount, 1)
    }

    func testDuplicateCoordinatesAcrossCandidateBandsResolveOnceWithinSearch() async throws {
        let resolver = MockSuitabilityResolver { _ in .suitable }
        let service = LocationSuitabilityService(resolver: resolver)
        let session = service.makeSearchSession()
        let cachedPoint = GridPoint(
            coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
            distanceMiles: 0,
            bearing: 0
        )

        _ = await session.suitability(for: [cachedPoint])
        let batchResults = await session.suitability(for: [
            cachedPoint,
            GridPoint(
                coordinate: Coordinate(latitude: 40.7148, longitude: -74.0080),
                distanceMiles: 1,
                bearing: 45
            )
        ])

        XCTAssertEqual(batchResults[cachedPoint], .suitable)
        let callCount = await resolver.callCount
        XCTAssertEqual(callCount, 2)
    }

    func testSecondSearchSessionResolvesSameCoordinateAgain() async throws {
        let resolver = MockSuitabilityResolver { _ in .suitable }
        let service = LocationSuitabilityService(resolver: resolver)
        let point = GridPoint(
            coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
            distanceMiles: 0,
            bearing: 0
        )

        let firstSearch = service.makeSearchSession()
        _ = await firstSearch.suitability(for: point)
        let secondSearch = service.makeSearchSession()
        _ = await secondSearch.suitability(for: point)

        let callCount = await resolver.callCount
        XCTAssertEqual(callCount, 2)
    }

    func testTransientFailureIsReusedWithinSearchButRetriedByNextSearch() async throws {
        let resolver = MockSuitabilityResolver { _ in .unknown(reason: .temporarilyUnavailable) }
        let service = LocationSuitabilityService(resolver: resolver)
        let point = GridPoint(
            coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
            distanceMiles: 0,
            bearing: 0
        )

        let firstSearch = service.makeSearchSession()
        _ = await firstSearch.suitability(for: point)
        _ = await firstSearch.suitability(for: point)
        let secondSearch = service.makeSearchSession()
        _ = await secondSearch.suitability(for: point)

        let callCount = await resolver.callCount
        XCTAssertEqual(callCount, 2)
    }

    func testFailedSearchDoesNotLeakSuitabilityCacheIntoNextSearch() async throws {
        let date = currentSearchDate()
        let resolver = SearchScopedResolver(
            unsuitableCallCount: BestSpotSearcher.maxSuitabilityCandidateChecks
        )
        let searcher = searcher(
            weather: MockWeatherProvider { _ in Self.nightForecasts(for: date, cloudCover: 5) },
            suitability: LocationSuitabilityService(resolver: resolver)
        )
        let center = CachedLocation(from: createSavedLocation())

        do {
            _ = try await searcher.findBestSpots(
                around: center,
                radiusMiles: 50,
                spacingMiles: 5,
                for: date,
                topN: 5
            )
            XCTFail("Expected the first search to have no recommendable locations")
        } catch BestSpotSearchError.noRecommendableLocations {
            XCTAssertTrue(true)
        }

        let secondResult = try await searcher.findBestSpots(
            around: center,
            radiusMiles: 50,
            spacingMiles: 5,
            for: date,
            topN: 5
        )

        XCTAssertEqual(secondResult.topLocations.count, 5)
        let callCount = await resolver.callCount
        XCTAssertEqual(callCount, BestSpotSearcher.maxSuitabilityCandidateChecks + BestSpotSearcher.suitabilityCandidateCount(topN: 5))
    }

    func testDuplicateRoundedCoordinatesInBatchTriggerOneResolverCall() async throws {
        let resolver = MockSuitabilityResolver { _ in .suitable }
        let service = LocationSuitabilityService(resolver: resolver)
        let session = service.makeSearchSession()
        let points = [
            GridPoint(
                coordinate: Coordinate(latitude: 40.71281, longitude: -74.00601),
                distanceMiles: 0,
                bearing: 0
            ),
            GridPoint(
                coordinate: Coordinate(latitude: 40.71284, longitude: -74.00604),
                distanceMiles: 0.1,
                bearing: 45
            )
        ]

        let results = await session.suitability(for: points)

        XCTAssertEqual(results.count, 2)
        let callCount = await resolver.callCount
        XCTAssertEqual(callCount, 1)
    }

    func testDefaultMaximumSuitabilityLookupConcurrencyIsFour() {
        XCTAssertEqual(LocationSuitabilityService.defaultMaxConcurrentLookups, 4)
    }

    func testCacheDoesNotMergeFarApartPoints() async throws {
        let resolver = MockSuitabilityResolver { _ in .suitable }
        let service = LocationSuitabilityService(resolver: resolver)
        let session = service.makeSearchSession()

        _ = await session.suitability(for: [
            GridPoint(
                coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
                distanceMiles: 0,
                bearing: 0
            ),
            GridPoint(
                coordinate: Coordinate(latitude: 40.7148, longitude: -74.0080),
                distanceMiles: 0,
                bearing: 0
            )
        ])

        let callCount = await resolver.callCount
        XCTAssertEqual(callCount, 2)
    }

    func testSuitableBeatsUnknownWhenOtherRankingFactorsAreEqual() {
        let unknown = LocationScore(
            point: GridPoint(
                coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
                distanceMiles: 1,
                bearing: 0
            ),
            score: 90,
            nightQuality: Self.testNightQuality(),
            fogScore: FogScore(score: 10, factors: []),
            avgCloudCover: 5,
            avgWindSpeed: 3,
            suitability: .unknown(reason: .notChecked),
            summary: "Good"
        )
        let suitable = unknown.with(suitability: .suitable)

        XCTAssertTrue(BestSpotSearcher.isHigherRanked(suitable, than: unknown))
    }

    func testRecommendationsRemainDeterministicWhenBatchResultsReturnOutOfOrder() async throws {
        let date = currentSearchDate()
        let weather = MockWeatherProvider { _ in
            Self.nightForecasts(for: date, cloudCover: 5)
        }
        let normalResult = try await searcher(
            weather: weather,
            suitability: MockSuitabilityProvider { _ in .suitable }
        ).findBestSpots(
            around: CachedLocation(from: createSavedLocation()),
            radiusMiles: 30,
            spacingMiles: 10,
            for: date,
            topN: 5
        )
        let reversedResult = try await searcher(
            weather: weather,
            suitability: ReversedBatchSuitabilityProvider()
        ).findBestSpots(
            around: CachedLocation(from: createSavedLocation()),
            radiusMiles: 30,
            spacingMiles: 10,
            for: date,
            topN: 5
        )

        XCTAssertEqual(
            normalResult.topLocations.map(\.point.coordinate),
            reversedResult.topLocations.map(\.point.coordinate)
        )
    }

    func testCenterImprovementUsesCenterFlag() async throws {
        let date = currentSearchDate()
        let searcher = searcher(
            weather: MockWeatherProvider { coordinate in
                let isCenter = abs(coordinate.latitude - 40.7128) < 0.0001 && abs(coordinate.longitude + 74.0060) < 0.0001
                return Self.nightForecasts(for: date, cloudCover: isCenter ? 70 : 5)
            },
            suitability: MockSuitabilityProvider { _ in .suitable }
        )

        let result = try await searcher.findBestSpots(
            around: CachedLocation(from: createSavedLocation()),
            radiusMiles: 10,
            spacingMiles: 10,
            for: date,
            topN: 5
        )

        XCTAssertNotNil(result.bestSpot?.improvementOverCenter)
        XCTAssertGreaterThan(result.bestSpot?.improvementOverCenter ?? 0, 0)
    }

    func testAllScoredLocationsAreSeparateFromTopRecommendations() async throws {
        let date = currentSearchDate()
        let searcher = searcher(weather: MockWeatherProvider { _ in
            Self.nightForecasts(for: date, cloudCover: 5)
        })

        let result = try await searcher.findBestSpots(
            around: CachedLocation(from: createSavedLocation()),
            radiusMiles: 30,
            spacingMiles: 10,
            for: date,
            topN: 5
        )

        XCTAssertGreaterThanOrEqual(result.allScoredLocations.count, result.topLocations.count)
        XCTAssertEqual(result.topLocations.count, 5)
        XCTAssertGreaterThan(result.allScoredLocations.count, result.topLocations.count)
        XCTAssertEqual(result.topLocations, Array(result.allScoredLocations.prefix(5)))
    }

    func testEqualScoreOrderingUsesDeterministicTieBreakers() async throws {
        let date = currentSearchDate()
        let searcher = searcher(weather: MockWeatherProvider { coordinate in
            let cloudCover = coordinate.latitude < 40.7128 ? 1 : 4
            return Self.nightForecasts(for: date, cloudCover: cloudCover)
        })

        let result = try await searcher.findBestSpots(
            around: CachedLocation(from: createSavedLocation()),
            radiusMiles: 10,
            spacingMiles: 10,
            for: date,
            topN: 5
        )

        let scores = result.topLocations.map(\.score)
        XCTAssertEqual(Set(scores).count, 1)
        XCTAssertLessThanOrEqual(result.topLocations[0].avgCloudCover, result.topLocations[1].avgCloudCover)
    }

    @MainActor
    func testViewModelExposesHelpfulErrorState() async {
        let viewModel = BestSpotViewModel(
            searcher: MockBestSpotSearching(error: BestSpotSearchError.noScorableLocations)
        )

        await viewModel.search(
            around: createSavedLocation(),
            for: currentSearchDate(),
            topN: 5
        )

        XCTAssertEqual(
            viewModel.error?.localizedDescription,
            "Weather data was available, but no night conditions could be scored for the selected date."
        )
    }

    @MainActor
    func testViewModelExposesNoRecommendableAreaErrorState() async {
        let viewModel = BestSpotViewModel(
            searcher: MockBestSpotSearching(error: BestSpotSearchError.noRecommendableLocations)
        )

        await viewModel.search(
            around: createSavedLocation(),
            for: currentSearchDate(),
            topN: 5
        )

        XCTAssertNil(viewModel.result?.bestSpot)
        XCTAssertEqual(
            viewModel.error?.localizedDescription,
            "No recommendable nearby areas found. The best-scoring candidates appear to be water or could not be verified. Try a different starting location, search radius, or date."
        )
    }
    
    // MARK: - Score Calculation Logic Tests
    
    func testGridPointEquality() {
        let coordinate = Coordinate(latitude: 40.7128, longitude: -74.0060)
        let point1 = GridPoint(coordinate: coordinate, distanceMiles: 10, bearing: 45, elevation: nil)
        let point2 = GridPoint(coordinate: coordinate, distanceMiles: 10, bearing: 45, elevation: nil)
        let point3 = GridPoint(coordinate: coordinate, distanceMiles: 20, bearing: 45, elevation: nil)
        
        XCTAssertEqual(point1, point2)
        XCTAssertNotEqual(point1, point3)
    }
    
    // MARK: - Search Parameters Validation
    
    func testDefaultSearchParameters() {
        // Default radius should be 30 miles
        XCTAssertEqual(BestSpotSettings.defaultSearchRadius, 30)
        // Default spacing should be 5 miles
        XCTAssertEqual(BestSpotSettings.defaultGridSpacing, 5)
    }
    
    func testSearchRadiusLimits() {
        XCTAssertEqual(BestSpotSettings.minSearchRadius, 10)
        XCTAssertEqual(BestSpotSettings.maxSearchRadius, 50)
    }
    
    func testGridSpacingLimits() {
        XCTAssertEqual(BestSpotSettings.minGridSpacing, 3)
        XCTAssertEqual(BestSpotSettings.maxGridSpacing, 10)
    }
    
    // MARK: - Location Score Validation Tests
    
    func testHighScoreHasGreenColor() {
        let point = GridPoint(
            coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
            distanceMiles: 10,
            bearing: 0
        )
        
        let nightQuality = NightQualityAssessment(
            rating: .excellent,
            summary: "Excellent conditions",
            details: NightQualityAssessment.Details(
                cloudCoverScore: 5.0,
                fogScoreAvg: 5.0,
                moonIlluminationAvg: 10,
                windSpeedAvg: 3.0
            ),
            bestWindow: nil,
            hourlyRatings: [],
            nightStart: Date(),
            nightEnd: Date().addingTimeInterval(3600 * 8)
        )
        
        let locationScore = LocationScore(
            point: point,
            score: 95,
            nightQuality: nightQuality,
            fogScore: FogScore(score: 5, factors: []),
            avgCloudCover: 5.0,
            avgWindSpeed: 3.0,
            summary: "Crystal clear skies, calm winds"
        )
        
        XCTAssertEqual(locationScore.scoreColor, "green")
    }
    
    func testMediumScoreHasBlueColor() {
        let point = GridPoint(
            coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
            distanceMiles: 10,
            bearing: 0
        )
        
        let nightQuality = NightQualityAssessment(
            rating: .good,
            summary: "Good conditions",
            details: NightQualityAssessment.Details(
                cloudCoverScore: 25.0,
                fogScoreAvg: 15.0,
                moonIlluminationAvg: 30,
                windSpeedAvg: 8.0
            ),
            bestWindow: nil,
            hourlyRatings: [],
            nightStart: Date(),
            nightEnd: Date().addingTimeInterval(3600 * 8)
        )
        
        let locationScore = LocationScore(
            point: point,
            score: 70,
            nightQuality: nightQuality,
            fogScore: FogScore(score: 15, factors: []),
            avgCloudCover: 25.0,
            avgWindSpeed: 8.0,
            summary: "Mostly clear, light winds"
        )
        
        XCTAssertEqual(locationScore.scoreColor, "blue")
    }
    
    func testLowScoreHasRedColor() {
        let point = GridPoint(
            coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
            distanceMiles: 10,
            bearing: 0
        )
        
        let nightQuality = NightQualityAssessment(
            rating: .poor,
            summary: "Poor conditions",
            details: NightQualityAssessment.Details(
                cloudCoverScore: 90.0,
                fogScoreAvg: 80.0,
                moonIlluminationAvg: 100,
                windSpeedAvg: 25.0
            ),
            bestWindow: nil,
            hourlyRatings: [],
            nightStart: Date(),
            nightEnd: Date().addingTimeInterval(3600 * 8)
        )
        
        let locationScore = LocationScore(
            point: point,
            score: 25,
            nightQuality: nightQuality,
            fogScore: FogScore(score: 80, factors: [.highHumidity]),
            avgCloudCover: 90.0,
            avgWindSpeed: 25.0,
            summary: "Cloudy, high fog risk"
        )
        
        XCTAssertEqual(locationScore.scoreColor, "red")
    }
    
    // MARK: - BestSpotResult Tests
    
    func testBestSpotResultWithMultipleScores() {
        let centerLocation = CachedLocation(
            name: "Test Center",
            latitude: 40.7128,
            longitude: -74.0060
        )
        
        let moonInfo = MoonInfo(
            phase: 0.25,
            phaseName: "First Quarter",
            altitude: 45.0,
            illumination: 50,
            emoji: "🌓"
        )
        
        let scoredLocations = (1...5).map { i in
            LocationScore(
                point: GridPoint(
                    coordinate: Coordinate(latitude: 40.7128 + Double(i) * 0.01, longitude: -74.0060),
                    distanceMiles: Double(i) * 5,
                    bearing: 0
                ),
                score: 100 - (i * 10),
                nightQuality: NightQualityAssessment(
                    rating: .good,
                    summary: "Good",
                    details: NightQualityAssessment.Details(
                        cloudCoverScore: 20.0,
                        fogScoreAvg: 10.0,
                        moonIlluminationAvg: 25,
                        windSpeedAvg: 5.0
                    ),
                    bestWindow: nil,
                    hourlyRatings: [],
                    nightStart: Date(),
                    nightEnd: Date().addingTimeInterval(3600 * 8)
                ),
                fogScore: FogScore(score: 10, factors: []),
                avgCloudCover: 20.0,
                avgWindSpeed: 5.0,
                summary: "Good conditions"
            )
        }
        
        let result = BestSpotResult(
            centerLocation: centerLocation,
            searchRadiusMiles: 30,
            gridSpacingMiles: 5,
            scoredLocations: scoredLocations,
            moonInfo: moonInfo,
            searchDate: Date(),
            searchDuration: 3.5
        )
        
        XCTAssertEqual(result.scoredLocations.count, 5)
        XCTAssertEqual(result.bestSpot?.score, 90) // First and highest
        XCTAssertEqual(result.topSpots.count, 5)
        XCTAssertEqual(result.searchDuration, 3.5)
    }
    
    // MARK: - Coordinate Hashable Tests
    
    func testCoordinateCanBeUsedAsDictionaryKey() {
        let coord1 = Coordinate(latitude: 40.7128, longitude: -74.0060)
        let coord2 = Coordinate(latitude: 40.7128, longitude: -74.0060)
        let coord3 = Coordinate(latitude: 34.0522, longitude: -118.2437)
        
        var dict: [Coordinate: String] = [:]
        dict[coord1] = "New York"
        
        XCTAssertEqual(dict[coord2], "New York")
        XCTAssertNil(dict[coord3])
    }
    
    // MARK: - Grid Point Generation Tests
    
    func testGridGenerationWithSmallRadius() {
        let center = Coordinate(latitude: 40.7128, longitude: -74.0060)
        let grid = GeographicGridGenerator.generateGrid(
            around: center,
            radiusMiles: 3,
            spacingMiles: 5
        )
        
        // With radius smaller than spacing, should only have center
        XCTAssertEqual(grid.count, 1)
    }
    
    func testGridGenerationWithLargeRadius() {
        let center = Coordinate(latitude: 40.7128, longitude: -74.0060)
        let grid = GeographicGridGenerator.generateGrid(
            around: center,
            radiusMiles: 50,
            spacingMiles: 10
        )
        
        // Should have many points: center + 5 rings
        XCTAssertGreaterThan(grid.count, 40)
        XCTAssertLessThan(grid.count, 120)
    }
}

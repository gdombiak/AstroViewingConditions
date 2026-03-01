import XCTest
import Foundation
@testable import AstroViewingConditions

final class BestSpotSearcherTests: XCTestCase {
    
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

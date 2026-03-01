import XCTest
import Foundation
@testable import AstroViewingConditions

final class LocationScoreTests: XCTestCase {
    
    // MARK: - Helper Methods
    
    private func createGridPoint(distance: Double, bearing: Double) -> GridPoint {
        GridPoint(
            coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
            distanceMiles: distance,
            bearing: bearing,
            elevation: nil
        )
    }
    
    private func createNightQuality(rating: NightQualityAssessment.Rating = .good) -> NightQualityAssessment {
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
    
    private func createFogScore(score: Int) -> FogScore {
        FogScore(score: score, factors: [.highHumidity])
    }
    
    // MARK: - LocationScore Initialization Tests
    
    func testLocationScoreInitialization() {
        let point = createGridPoint(distance: 10.5, bearing: 45)
        let nightQuality = createNightQuality()
        let fogScore = createFogScore(score: 20)
        
        let locationScore = LocationScore(
            point: point,
            score: 75,
            nightQuality: nightQuality,
            fogScore: fogScore,
            avgCloudCover: 15.5,
            avgWindSpeed: 8.2,
            summary: "Mostly clear with light winds"
        )
        
        XCTAssertEqual(locationScore.score, 75)
        XCTAssertEqual(locationScore.point.distanceMiles, 10.5)
        XCTAssertEqual(locationScore.point.bearing, 45)
        XCTAssertEqual(locationScore.avgCloudCover, 15.5)
        XCTAssertEqual(locationScore.avgWindSpeed, 8.2)
        XCTAssertEqual(locationScore.summary, "Mostly clear with light winds")
        XCTAssertEqual(locationScore.fogScore.score, 20)
    }
    
    func testLocationScoreIdIsUnique() {
        let point = createGridPoint(distance: 10, bearing: 0)
        let nightQuality = createNightQuality()
        let fogScore = createFogScore(score: 10)
        
        let score1 = LocationScore(
            point: point,
            score: 80,
            nightQuality: nightQuality,
            fogScore: fogScore,
            avgCloudCover: 10,
            avgWindSpeed: 5,
            summary: "Test"
        )
        
        let score2 = LocationScore(
            point: point,
            score: 80,
            nightQuality: nightQuality,
            fogScore: fogScore,
            avgCloudCover: 10,
            avgWindSpeed: 5,
            summary: "Test"
        )
        
        XCTAssertNotEqual(score1.id, score2.id)
    }
    
    // MARK: - Distance String Tests
    
    func testDistanceStringLessThanOneMile() {
        let point = createGridPoint(distance: 0.5, bearing: 45)
        let locationScore = LocationScore(
            point: point,
            score: 80,
            nightQuality: createNightQuality(),
            fogScore: createFogScore(score: 10),
            avgCloudCover: 10,
            avgWindSpeed: 5,
            summary: "Test"
        )
        
        XCTAssertEqual(locationScore.distanceString, "0.5 mi")
    }
    
    func testDistanceStringWholeNumber() {
        let point = createGridPoint(distance: 10.0, bearing: 45)
        let locationScore = LocationScore(
            point: point,
            score: 80,
            nightQuality: createNightQuality(),
            fogScore: createFogScore(score: 10),
            avgCloudCover: 10,
            avgWindSpeed: 5,
            summary: "Test"
        )
        
        XCTAssertEqual(locationScore.distanceString, "10.0 mi")
    }
    
    func testDistanceStringDecimal() {
        let point = createGridPoint(distance: 12.34, bearing: 45)
        let locationScore = LocationScore(
            point: point,
            score: 80,
            nightQuality: createNightQuality(),
            fogScore: createFogScore(score: 10),
            avgCloudCover: 10,
            avgWindSpeed: 5,
            summary: "Test"
        )
        
        XCTAssertEqual(locationScore.distanceString, "12.3 mi")
    }
    
    // MARK: - Bearing String Tests
    
    func testBearingStringNorth() {
        let point = createGridPoint(distance: 10, bearing: 0)
        let locationScore = LocationScore(
            point: point,
            score: 80,
            nightQuality: createNightQuality(),
            fogScore: createFogScore(score: 10),
            avgCloudCover: 10,
            avgWindSpeed: 5,
            summary: "Test"
        )
        
        XCTAssertEqual(locationScore.bearingString, "N")
    }
    
    func testBearingStringEast() {
        let point = createGridPoint(distance: 10, bearing: 90)
        let locationScore = LocationScore(
            point: point,
            score: 80,
            nightQuality: createNightQuality(),
            fogScore: createFogScore(score: 10),
            avgCloudCover: 10,
            avgWindSpeed: 5,
            summary: "Test"
        )
        
        XCTAssertEqual(locationScore.bearingString, "E")
    }
    
    func testBearingStringSouth() {
        let point = createGridPoint(distance: 10, bearing: 180)
        let locationScore = LocationScore(
            point: point,
            score: 80,
            nightQuality: createNightQuality(),
            fogScore: createFogScore(score: 10),
            avgCloudCover: 10,
            avgWindSpeed: 5,
            summary: "Test"
        )
        
        XCTAssertEqual(locationScore.bearingString, "S")
    }
    
    func testBearingStringWest() {
        let point = createGridPoint(distance: 10, bearing: 270)
        let locationScore = LocationScore(
            point: point,
            score: 80,
            nightQuality: createNightQuality(),
            fogScore: createFogScore(score: 10),
            avgCloudCover: 10,
            avgWindSpeed: 5,
            summary: "Test"
        )
        
        XCTAssertEqual(locationScore.bearingString, "W")
    }
    
    // MARK: - Full Location String Tests
    
    func testFullLocationString() {
        let point = createGridPoint(distance: 15.5, bearing: 45)
        let locationScore = LocationScore(
            point: point,
            score: 80,
            nightQuality: createNightQuality(),
            fogScore: createFogScore(score: 10),
            avgCloudCover: 10,
            avgWindSpeed: 5,
            summary: "Test"
        )
        
        XCTAssertEqual(locationScore.fullLocationString, "15.5 mi NE")
    }
    
    // MARK: - Score Color Tests
    
    func testScoreColorGreen() {
        let point = createGridPoint(distance: 10, bearing: 0)
        
        for score in [80, 90, 100] {
            let locationScore = LocationScore(
                point: point,
                score: score,
                nightQuality: createNightQuality(),
                fogScore: createFogScore(score: 10),
                avgCloudCover: 10,
                avgWindSpeed: 5,
                summary: "Test"
            )
            XCTAssertEqual(locationScore.scoreColor, "green")
        }
    }
    
    func testScoreColorBlue() {
        let point = createGridPoint(distance: 10, bearing: 0)
        
        for score in [60, 70, 79] {
            let locationScore = LocationScore(
                point: point,
                score: score,
                nightQuality: createNightQuality(),
                fogScore: createFogScore(score: 10),
                avgCloudCover: 10,
                avgWindSpeed: 5,
                summary: "Test"
            )
            XCTAssertEqual(locationScore.scoreColor, "blue")
        }
    }
    
    func testScoreColorOrange() {
        let point = createGridPoint(distance: 10, bearing: 0)
        
        for score in [40, 50, 59] {
            let locationScore = LocationScore(
                point: point,
                score: score,
                nightQuality: createNightQuality(),
                fogScore: createFogScore(score: 10),
                avgCloudCover: 10,
                avgWindSpeed: 5,
                summary: "Test"
            )
            XCTAssertEqual(locationScore.scoreColor, "orange")
        }
    }
    
    func testScoreColorRed() {
        let point = createGridPoint(distance: 10, bearing: 0)
        
        for score in [0, 20, 39] {
            let locationScore = LocationScore(
                point: point,
                score: score,
                nightQuality: createNightQuality(),
                fogScore: createFogScore(score: 10),
                avgCloudCover: 10,
                avgWindSpeed: 5,
                summary: "Test"
            )
            XCTAssertEqual(locationScore.scoreColor, "red")
        }
    }
    
    // MARK: - BestSpotResult Tests
    
    func testBestSpotResultInitialization() {
        let centerLocation = CachedLocation(
            name: "Test Location",
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
        
        let scoredLocations = [
            LocationScore(
                point: createGridPoint(distance: 5, bearing: 0),
                score: 85,
                nightQuality: createNightQuality(rating: .excellent),
                fogScore: createFogScore(score: 5),
                avgCloudCover: 5,
                avgWindSpeed: 3,
                summary: "Excellent"
            ),
            LocationScore(
                point: createGridPoint(distance: 10, bearing: 90),
                score: 70,
                nightQuality: createNightQuality(rating: .good),
                fogScore: createFogScore(score: 15),
                avgCloudCover: 20,
                avgWindSpeed: 8,
                summary: "Good"
            )
        ]
        
        let result = BestSpotResult(
            centerLocation: centerLocation,
            searchRadiusMiles: 30,
            gridSpacingMiles: 5,
            scoredLocations: scoredLocations,
            moonInfo: moonInfo,
            searchDate: Date(),
            searchDuration: 2.5
        )
        
        XCTAssertEqual(result.centerLocation.name, "Test Location")
        XCTAssertEqual(result.searchRadiusMiles, 30)
        XCTAssertEqual(result.gridSpacingMiles, 5)
        XCTAssertEqual(result.scoredLocations.count, 2)
        XCTAssertEqual(result.moonInfo.illumination, 50)
        XCTAssertEqual(result.searchDuration, 2.5)
    }
    
    func testBestSpotReturnsFirstLocation() {
        let centerLocation = CachedLocation(
            name: "Test",
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
        
        let scoredLocations = [
            LocationScore(
                point: createGridPoint(distance: 5, bearing: 0),
                score: 90,
                nightQuality: createNightQuality(),
                fogScore: createFogScore(score: 5),
                avgCloudCover: 5,
                avgWindSpeed: 3,
                summary: "Best"
            ),
            LocationScore(
                point: createGridPoint(distance: 10, bearing: 90),
                score: 70,
                nightQuality: createNightQuality(),
                fogScore: createFogScore(score: 15),
                avgCloudCover: 20,
                avgWindSpeed: 8,
                summary: "Second"
            )
        ]
        
        let result = BestSpotResult(
            centerLocation: centerLocation,
            searchRadiusMiles: 30,
            gridSpacingMiles: 5,
            scoredLocations: scoredLocations,
            moonInfo: moonInfo,
            searchDate: Date(),
            searchDuration: 2.5
        )
        
        XCTAssertEqual(result.bestSpot?.score, 90)
        XCTAssertEqual(result.bestSpot?.summary, "Best")
    }
    
    func testBestSpotReturnsNilForEmptyResults() {
        let centerLocation = CachedLocation(
            name: "Test",
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
        
        let result = BestSpotResult(
            centerLocation: centerLocation,
            searchRadiusMiles: 30,
            gridSpacingMiles: 5,
            scoredLocations: [],
            moonInfo: moonInfo,
            searchDate: Date(),
            searchDuration: 2.5
        )
        
        XCTAssertNil(result.bestSpot)
        XCTAssertTrue(result.topSpots.isEmpty)
    }
    
    func testTopSpotsReturnsAllLocations() {
        let centerLocation = CachedLocation(
            name: "Test",
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
        
        let scoredLocations = [
            LocationScore(
                point: createGridPoint(distance: 5, bearing: 0),
                score: 90,
                nightQuality: createNightQuality(),
                fogScore: createFogScore(score: 5),
                avgCloudCover: 5,
                avgWindSpeed: 3,
                summary: "First"
            ),
            LocationScore(
                point: createGridPoint(distance: 10, bearing: 90),
                score: 80,
                nightQuality: createNightQuality(),
                fogScore: createFogScore(score: 15),
                avgCloudCover: 20,
                avgWindSpeed: 8,
                summary: "Second"
            ),
            LocationScore(
                point: createGridPoint(distance: 15, bearing: 180),
                score: 70,
                nightQuality: createNightQuality(),
                fogScore: createFogScore(score: 20),
                avgCloudCover: 30,
                avgWindSpeed: 10,
                summary: "Third"
            )
        ]
        
        let result = BestSpotResult(
            centerLocation: centerLocation,
            searchRadiusMiles: 30,
            gridSpacingMiles: 5,
            scoredLocations: scoredLocations,
            moonInfo: moonInfo,
            searchDate: Date(),
            searchDuration: 2.5
        )
        
        XCTAssertEqual(result.topSpots.count, 3)
    }
}

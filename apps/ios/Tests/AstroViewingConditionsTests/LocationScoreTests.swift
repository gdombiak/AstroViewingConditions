import SharedCode
import XCTest
import Foundation
@testable import AstroViewingConditions

@MainActor
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

    func testOnlyRecommendableLocationScoresCanOpenInMaps() {
        let point = createGridPoint(distance: 10.5, bearing: 45)

        let suitable = LocationScore(
            point: point,
            score: 75,
            nightQuality: createNightQuality(),
            fogScore: createFogScore(score: 20),
            avgCloudCover: 15.5,
            avgWindSpeed: 8.2,
            suitability: .suitable,
            summary: "Mostly clear with light winds"
        )
        let unchecked = suitable.with(suitability: .unchecked)
        let unsuitable = suitable.with(suitability: .unsuitable(reason: "Water area"))

        XCTAssertTrue(suitable.canOpenInMaps)
        XCTAssertFalse(unchecked.canOpenInMaps)
        XCTAssertFalse(unsuitable.canOpenInMaps)
        XCTAssertEqual(unchecked.suitability.label, "Weather-only estimate. Access not checked.")
    }

    // MARK: - Suitability verification labels

    func testGeocodingFailedLabelClarifiesLandAreaVerification() {
        XCTAssertEqual(
            LocationSuitabilityStatus.unknown(reason: .geocodingFailed).label,
            "Land check unavailable"
        )
    }

    func testTemporarilyUnavailableLabelClarifiesLandAreaVerification() {
        XCTAssertEqual(
            LocationSuitabilityStatus.unknown(reason: .temporarilyUnavailable).label,
            "Land check temporarily unavailable"
        )
    }

    // MARK: - Improvement comparison copy

    private func locationWithImprovement(_ delta: Int?, publicScore: Int = 80, nightScore: Int = 90) -> LocationScore {
        LocationScore(
            point: createGridPoint(distance: 5, bearing: 90),
            score: publicScore,
            nightConditionsScore: nightScore,
            nightQuality: createNightQuality(),
            fogScore: createFogScore(score: 10),
            avgCloudCover: 10,
            avgWindSpeed: 5,
            suitability: .suitable,
            improvementOverCenter: delta,
            summary: "Mostly clear"
        )
    }

    func testImprovementVisiblePositiveSingular() {
        let score = locationWithImprovement(1)
        XCTAssertEqual(score.improvementSummary(comparedTo: "Home"), "+1 vs Home")
    }

    func testImprovementVisiblePositivePlural() {
        let score = locationWithImprovement(4)
        XCTAssertEqual(score.improvementSummary(comparedTo: "Home"), "+4 vs Home")
    }

    func testImprovementVisibleZero() {
        let score = locationWithImprovement(0)
        XCTAssertEqual(score.improvementSummary(comparedTo: "Home"), "Same as Home")
    }

    func testImprovementVisibleNegativeUsesMinusSignAndCenterName() {
        let score = locationWithImprovement(-2)
        XCTAssertEqual(score.improvementSummary(comparedTo: "Home"), "−2 vs Home")
        XCTAssertTrue(score.improvementSummary(comparedTo: "Home")?.contains("−") == true)
    }

    func testImprovementVisibleUsesActualCenterName() {
        let score = locationWithImprovement(3)
        XCTAssertEqual(score.improvementSummary(comparedTo: "Stub Stewart"), "+3 vs Stub Stewart")
        XCTAssertEqual(score.improvementSummary(comparedTo: "Portland"), "+3 vs Portland")
    }

    func testImprovementVisibleNilWhenNoCenterComparison() {
        let score = locationWithImprovement(nil)
        XCTAssertNil(score.improvementSummary(comparedTo: "Home"))
    }

    func testImprovementAccessibilityPositiveSingular() {
        let score = locationWithImprovement(1)
        XCTAssertEqual(
            score.improvementAccessibilityDescription(comparedTo: "Home"),
            "1 point better than Home"
        )
    }

    func testImprovementAccessibilityPositivePlural() {
        let score = locationWithImprovement(4)
        XCTAssertEqual(
            score.improvementAccessibilityDescription(comparedTo: "Home"),
            "4 points better than Home"
        )
    }

    func testImprovementAccessibilityZero() {
        let score = locationWithImprovement(0)
        XCTAssertEqual(
            score.improvementAccessibilityDescription(comparedTo: "Home"),
            "Same score as Home"
        )
    }

    func testImprovementAccessibilityNegative() {
        let score = locationWithImprovement(-2)
        XCTAssertEqual(
            score.improvementAccessibilityDescription(comparedTo: "Home"),
            "2 points below Home"
        )
        let singular = locationWithImprovement(-1)
        XCTAssertEqual(
            singular.improvementAccessibilityDescription(comparedTo: "Home"),
            "1 point below Home"
        )
    }

    func testImprovementAccessibilityUsesActualCenterName() {
        let score = locationWithImprovement(5)
        XCTAssertEqual(
            score.improvementAccessibilityDescription(comparedTo: "Stub Stewart"),
            "5 points better than Stub Stewart"
        )
    }

    func testWithImprovementUsesPublicScoreNotNightScore() {
        // Public OQ score 80 vs center 70 → +10; night score 95 must not be used.
        let base = locationWithImprovement(nil, publicScore: 80, nightScore: 95)
        let updated = base.withImprovement(comparedTo: 70)
        XCTAssertEqual(updated.improvementOverCenter, 10)
        XCTAssertEqual(updated.score, 80)
        XCTAssertEqual(updated.nightConditionsScore, 95)
        XCTAssertEqual(updated.improvementSummary(comparedTo: "Home"), "+10 vs Home")
        XCTAssertEqual(
            updated.improvementAccessibilityDescription(comparedTo: "Home"),
            "10 points better than Home"
        )
        XCTAssertFalse(updated.improvementSummary(comparedTo: "Home")?.contains("95") == true)
    }

    func testOldQualitativeImprovementPhrasesAreGone() {
        for delta in [-5, 0, 1, 4, 12, 25] {
            let score = locationWithImprovement(delta)
            let visible = score.improvementSummary(comparedTo: "Home") ?? ""
            let a11y = score.improvementAccessibilityDescription(comparedTo: "Home") ?? ""
            for phrase in [
                "Small improvement",
                "Worth considering",
                "Strong improvement",
                "Not meaningfully better than your location",
                "Current location not scored",
            ] {
                XCTAssertFalse(visible.contains(phrase), "visible still has '\(phrase)' for delta \(delta)")
                XCTAssertFalse(a11y.contains(phrase), "a11y still has '\(phrase)' for delta \(delta)")
            }
        }
    }

    func testResultCardAccessibilityIncludesDescriptiveImprovementNotCompactForm() {
        let score = locationWithImprovement(4, publicScore: 84, nightScore: 90)
        let label = BestSpotResultCard.accessibilityLabel(
            locationScore: score,
            rank: 1,
            scoringMode: .observingQuality,
            centerLocationName: "Home"
        )
        XCTAssertTrue(label.contains("4 points better than Home"))
        XCTAssertFalse(label.contains("+4 vs Home"), "VoiceOver must not duplicate compact form")
        XCTAssertTrue(label.contains("Observing quality score 84 out of 100"))
        XCTAssertFalse(label.contains("90"), "must not surface nightConditionsScore in OQ mode")
    }

    func testDefaultBestSpotMapAnnotationsUseTopLocationsOnly() {
        let first = LocationScore(
            point: createGridPoint(distance: 4, bearing: 90),
            score: 88,
            nightQuality: createNightQuality(),
            fogScore: createFogScore(score: 5),
            avgCloudCover: 4,
            avgWindSpeed: 3,
            suitability: .suitable,
            summary: "Clear"
        )
        let second = LocationScore(
            point: createGridPoint(distance: 6, bearing: 135),
            score: 82,
            nightQuality: createNightQuality(),
            fogScore: createFogScore(score: 8),
            avgCloudCover: 6,
            avgWindSpeed: 4,
            suitability: .suitable,
            summary: "Clear"
        )
        let background = LocationScore(
            point: createGridPoint(distance: 8, bearing: 180),
            score: 78,
            nightQuality: createNightQuality(),
            fogScore: createFogScore(score: 10),
            avgCloudCover: 8,
            avgWindSpeed: 4,
            suitability: .suitable,
            summary: "Mostly clear"
        )

        let items = BestSpotMapView.annotationItems(
            scoredLocations: [first, second, background],
            topLocations: [first, second]
        )

        XCTAssertEqual(items.map(\.location), [first, second])
        XCTAssertEqual(items.map(\.role), [.recommendation(rank: 1), .recommendation(rank: 2)])
    }

    func testWeatherFieldMapModeCanStillClassifyBackgroundContext() {
        let top = LocationScore(
            point: createGridPoint(distance: 4, bearing: 90),
            score: 88,
            nightQuality: createNightQuality(),
            fogScore: createFogScore(score: 5),
            avgCloudCover: 4,
            avgWindSpeed: 3,
            suitability: .suitable,
            summary: "Clear"
        )
        let background = LocationScore(
            point: createGridPoint(distance: 8, bearing: 180),
            score: 78,
            nightQuality: createNightQuality(),
            fogScore: createFogScore(score: 10),
            avgCloudCover: 8,
            avgWindSpeed: 4,
            suitability: .suitable,
            summary: "Mostly clear"
        )

        XCTAssertEqual(
            BestSpotMapView.markerRole(for: top, topLocations: [top]),
            .recommendation(rank: 1)
        )
        XCTAssertEqual(
            BestSpotMapView.markerRole(for: background, topLocations: [top]),
            .context
        )

        let items = BestSpotMapView.annotationItems(
            scoredLocations: [top, background],
            topLocations: [top],
            mode: .weatherField
        )
        XCTAssertEqual(items.map(\.role), [.recommendation(rank: 1), .context])
    }

    func testDefaultBestSpotMapExcludesUncheckedBackgroundLocations() {
        let recommended = LocationScore(
            point: createGridPoint(distance: 4, bearing: 90),
            score: 88,
            nightQuality: createNightQuality(),
            fogScore: createFogScore(score: 5),
            avgCloudCover: 4,
            avgWindSpeed: 3,
            suitability: .suitable,
            summary: "Clear"
        )
        let uncheckedBackground = recommended.with(suitability: .unchecked)

        let items = BestSpotMapView.annotationItems(
            scoredLocations: [recommended, uncheckedBackground],
            topLocations: [recommended]
        )

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.location, recommended)
        XCTAssertFalse(items.contains { $0.location.suitability == .unchecked })
    }

    func testSelectedBackgroundMapPointDoesNotExposeDestinationAction() {
        let background = LocationScore(
            point: createGridPoint(distance: 8, bearing: 180),
            score: 78,
            nightQuality: createNightQuality(),
            fogScore: createFogScore(score: 10),
            avgCloudCover: 8,
            avgWindSpeed: 4,
            suitability: .suitable,
            summary: "Mostly clear"
        )
        let uncheckedRecommendation = background.with(suitability: .unchecked)

        XCTAssertFalse(BestSpotSelectedMapLocationView.canOpenInMaps(location: background, rank: nil))
        XCTAssertFalse(BestSpotSelectedMapLocationView.canOpenInMaps(location: uncheckedRecommendation, rank: 1))
        XCTAssertTrue(BestSpotSelectedMapLocationView.canOpenInMaps(location: background, rank: 1))
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

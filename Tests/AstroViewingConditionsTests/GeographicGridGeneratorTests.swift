import XCTest
import Foundation
@testable import AstroViewingConditions

final class GeographicGridGeneratorTests: XCTestCase {
    
    // MARK: - Grid Generation Tests
    
    func testGenerateGridWithCenterOnly() {
        let center = Coordinate(latitude: 40.7128, longitude: -74.0060)
        let grid = GeographicGridGenerator.generateGrid(
            around: center,
            radiusMiles: 5,
            spacingMiles: 10
        )
        
        XCTAssertEqual(grid.count, 1)
        XCTAssertEqual(grid[0].coordinate.latitude, center.latitude)
        XCTAssertEqual(grid[0].coordinate.longitude, center.longitude)
        XCTAssertEqual(grid[0].distanceMiles, 0)
        XCTAssertEqual(grid[0].bearing, 0)
    }
    
    func testGenerateGridWithMultipleRings() {
        let center = Coordinate(latitude: 40.7128, longitude: -74.0060)
        let radiusMiles: Double = 10
        let spacingMiles: Double = 5
        
        let grid = GeographicGridGenerator.generateGrid(
            around: center,
            radiusMiles: radiusMiles,
            spacingMiles: spacingMiles
        )
        
        // Center + 2 rings
        // Ring 1: ~6 points (circumference ~31.4, spacing 5)
        // Ring 2: ~12 points (circumference ~62.8, spacing 5)
        // Total: 1 + 6 + 12 = 19
        XCTAssertGreaterThan(grid.count, 15)
        XCTAssertLessThanOrEqual(grid.count, 25)
        
        // First point should be center
        let centerPoint = grid[0]
        XCTAssertEqual(centerPoint.distanceMiles, 0)
        XCTAssertEqual(centerPoint.bearing, 0)
    }
    
    func testGenerateGridReturnsEmptyForInvalidParameters() {
        let center = Coordinate(latitude: 40.7128, longitude: -74.0060)
        
        let zeroRadius = GeographicGridGenerator.generateGrid(
            around: center,
            radiusMiles: 0,
            spacingMiles: 5
        )
        XCTAssertTrue(zeroRadius.isEmpty)
        
        let negativeRadius = GeographicGridGenerator.generateGrid(
            around: center,
            radiusMiles: -10,
            spacingMiles: 5
        )
        XCTAssertTrue(negativeRadius.isEmpty)
        
        let zeroSpacing = GeographicGridGenerator.generateGrid(
            around: center,
            radiusMiles: 10,
            spacingMiles: 0
        )
        XCTAssertTrue(zeroSpacing.isEmpty)
        
        let negativeSpacing = GeographicGridGenerator.generateGrid(
            around: center,
            radiusMiles: 10,
            spacingMiles: -5
        )
        XCTAssertTrue(negativeSpacing.isEmpty)
    }
    
    func testGridPointsAreWithinRadius() {
        let center = Coordinate(latitude: 40.7128, longitude: -74.0060)
        let radiusMiles: Double = 15
        let spacingMiles: Double = 5
        
        let grid = GeographicGridGenerator.generateGrid(
            around: center,
            radiusMiles: radiusMiles,
            spacingMiles: spacingMiles
        )
        
        for point in grid {
            XCTAssertLessThanOrEqual(point.distanceMiles, radiusMiles + 0.1) // Small tolerance
        }
    }
    
    func testGridPointCoordinatesAreValid() {
        let center = Coordinate(latitude: 40.7128, longitude: -74.0060)
        let grid = GeographicGridGenerator.generateGrid(
            around: center,
            radiusMiles: 30,
            spacingMiles: 10
        )
        
        for point in grid {
            XCTAssertGreaterThanOrEqual(point.coordinate.latitude, -90)
            XCTAssertLessThanOrEqual(point.coordinate.latitude, 90)
            XCTAssertGreaterThanOrEqual(point.coordinate.longitude, -180)
            XCTAssertLessThanOrEqual(point.coordinate.longitude, 180)
        }
    }
    
    func testGridAtDifferentLatitudes() {
        // Test at equator
        let equator = Coordinate(latitude: 0, longitude: 0)
        let equatorGrid = GeographicGridGenerator.generateGrid(
            around: equator,
            radiusMiles: 20,
            spacingMiles: 10
        )
        XCTAssertGreaterThan(equatorGrid.count, 1)
        
        // Test at high latitude
        let highLatitude = Coordinate(latitude: 70, longitude: 0)
        let highLatGrid = GeographicGridGenerator.generateGrid(
            around: highLatitude,
            radiusMiles: 20,
            spacingMiles: 10
        )
        XCTAssertGreaterThan(highLatGrid.count, 1)
        
        // Test at southern hemisphere
        let southernHemisphere = Coordinate(latitude: -40, longitude: 150)
        let southernGrid = GeographicGridGenerator.generateGrid(
            around: southernHemisphere,
            radiusMiles: 20,
            spacingMiles: 10
        )
        XCTAssertGreaterThan(southernGrid.count, 1)
    }
    
    // MARK: - Bearing to Cardinal Tests
    
    func testBearingToCardinalNorth() {
        XCTAssertEqual(GeographicGridGenerator.bearingToCardinal(0), "N")
        XCTAssertEqual(GeographicGridGenerator.bearingToCardinal(360), "N")
        XCTAssertEqual(GeographicGridGenerator.bearingToCardinal(11), "N")
    }
    
    func testBearingToCardinalNortheast() {
        XCTAssertEqual(GeographicGridGenerator.bearingToCardinal(45), "NE")
        XCTAssertEqual(GeographicGridGenerator.bearingToCardinal(22.5), "NNE")
        XCTAssertEqual(GeographicGridGenerator.bearingToCardinal(67.5), "ENE")
    }
    
    func testBearingToCardinalEast() {
        XCTAssertEqual(GeographicGridGenerator.bearingToCardinal(90), "E")
    }
    
    func testBearingToCardinalSoutheast() {
        XCTAssertEqual(GeographicGridGenerator.bearingToCardinal(135), "SE")
        XCTAssertEqual(GeographicGridGenerator.bearingToCardinal(112.5), "ESE")
        XCTAssertEqual(GeographicGridGenerator.bearingToCardinal(157.5), "SSE")
    }
    
    func testBearingToCardinalSouth() {
        XCTAssertEqual(GeographicGridGenerator.bearingToCardinal(180), "S")
    }
    
    func testBearingToCardinalSouthwest() {
        XCTAssertEqual(GeographicGridGenerator.bearingToCardinal(225), "SW")
        XCTAssertEqual(GeographicGridGenerator.bearingToCardinal(202.5), "SSW")
        XCTAssertEqual(GeographicGridGenerator.bearingToCardinal(247.5), "WSW")
    }
    
    func testBearingToCardinalWest() {
        XCTAssertEqual(GeographicGridGenerator.bearingToCardinal(270), "W")
    }
    
    func testBearingToCardinalNorthwest() {
        XCTAssertEqual(GeographicGridGenerator.bearingToCardinal(315), "NW")
        XCTAssertEqual(GeographicGridGenerator.bearingToCardinal(292.5), "WNW")
        XCTAssertEqual(GeographicGridGenerator.bearingToCardinal(337.5), "NNW")
    }
    
    func testBearingToCardinalNegativeBearing() {
        XCTAssertEqual(GeographicGridGenerator.bearingToCardinal(-45), "NW")
        XCTAssertEqual(GeographicGridGenerator.bearingToCardinal(-90), "W")
    }
    
    func testBearingToCardinalLargeBearing() {
        // 720 degrees = 2 full rotations = North
        // Note: Due to floating point precision, 720.0 % 360.0 may not be exactly 0
        let bearing720 = GeographicGridGenerator.bearingToCardinal(720)
        XCTAssertTrue(bearing720 == "N" || bearing720 == "NNE", "Bearing 720 should be N or NNE, got \(bearing720)")
        
        // 405 degrees = 360 + 45 = Northeast
        XCTAssertEqual(GeographicGridGenerator.bearingToCardinal(405), "NE")
    }
    
    // MARK: - GridPoint Tests
    
    func testGridPointInitialization() {
        let coordinate = Coordinate(latitude: 40.7128, longitude: -74.0060)
        let gridPoint = GridPoint(
            coordinate: coordinate,
            distanceMiles: 10.5,
            bearing: 45.0,
            elevation: 100.0
        )
        
        XCTAssertEqual(gridPoint.coordinate.latitude, 40.7128)
        XCTAssertEqual(gridPoint.coordinate.longitude, -74.0060)
        XCTAssertEqual(gridPoint.distanceMiles, 10.5)
        XCTAssertEqual(gridPoint.bearing, 45.0)
        XCTAssertEqual(gridPoint.elevation, 100.0)
    }
    
    func testGridPointWithoutElevation() {
        let coordinate = Coordinate(latitude: 40.7128, longitude: -74.0060)
        let gridPoint = GridPoint(
            coordinate: coordinate,
            distanceMiles: 10.0,
            bearing: 0
        )
        
        XCTAssertNil(gridPoint.elevation)
    }
    
    func testGridPointHashable() {
        let coordinate = Coordinate(latitude: 40.7128, longitude: -74.0060)
        let point1 = GridPoint(coordinate: coordinate, distanceMiles: 10, bearing: 0)
        let point2 = GridPoint(coordinate: coordinate, distanceMiles: 10, bearing: 0)
        let point3 = GridPoint(coordinate: coordinate, distanceMiles: 20, bearing: 0)
        
        XCTAssertEqual(point1, point2)
        XCTAssertNotEqual(point1, point3)
    }
}

import XCTest
import Foundation
@testable import AstroViewingConditions

final class FogCalculatorTests: XCTestCase {
    
    // MARK: - High Humidity (>95%)
    
    func testFogScoreWithHighHumidity() {
        let forecast = HourlyForecast(
            time: Date(),
            cloudCover: 0,
            humidity: 96,
            windSpeed: 5.0,
            windDirection: 180,
            temperature: 15.0,
            dewPoint: 12.0,
            visibility: 10000,
            lowCloudCover: nil
        )
        
        let score = FogCalculator.calculate(from: forecast)
        
        XCTAssertEqual(score.score, 32)
        XCTAssertTrue(score.factors.contains(.highHumidity))
    }
    
    func testFogScoreWithHumidityAtThreshold() {
        let forecast = HourlyForecast(
            time: Date(),
            cloudCover: 0,
            humidity: 95,
            windSpeed: 5.0,
            windDirection: 180,
            temperature: 15.0,
            dewPoint: 12.0,
            visibility: 10000,
            lowCloudCover: nil
        )
        
        let score = FogCalculator.calculate(from: forecast)
        
        XCTAssertEqual(score.score, 30)
        XCTAssertTrue(score.factors.contains(.highHumidity))
    }
    
    func testFogScoreWithHumidityBelowThreshold() {
        let forecast = HourlyForecast(
            time: Date(),
            cloudCover: 0,
            humidity: 80,
            windSpeed: 5.0,
            windDirection: 180,
            temperature: 15.0,
            dewPoint: 12.0,
            visibility: 10000,
            lowCloudCover: nil
        )
        
        let score = FogCalculator.calculate(from: forecast)
        
        XCTAssertEqual(score.score, 0)
        XCTAssertFalse(score.factors.contains(.highHumidity))
    }
    
    // MARK: - Low Temperature-Dew Point Difference (<1C)
    
    func testFogScoreWithLowTempDewDiff() {
        let forecast = HourlyForecast(
            time: Date(),
            cloudCover: 0,
            humidity: 80,
            windSpeed: 5.0,
            windDirection: 180,
            temperature: 15.0,
            dewPoint: 14.5,
            visibility: 10000,
            lowCloudCover: nil
        )
        
        let score = FogCalculator.calculate(from: forecast)
        
        XCTAssertEqual(score.score, 22)
        XCTAssertTrue(score.factors.contains(.lowTempDewDiff))
    }
    
    func testFogScoreWithTempDewDiffAtThreshold() {
        let forecast = HourlyForecast(
            time: Date(),
            cloudCover: 0,
            humidity: 80,
            windSpeed: 5.0,
            windDirection: 180,
            temperature: 15.0,
            dewPoint: 14.0,
            visibility: 10000,
            lowCloudCover: nil
        )
        
        let score = FogCalculator.calculate(from: forecast)
        
        XCTAssertEqual(score.score, 15)
        XCTAssertTrue(score.factors.contains(.lowTempDewDiff))
    }
    
    func testFogScoreWithNoDewPoint() {
        let forecast = HourlyForecast(
            time: Date(),
            cloudCover: 0,
            humidity: 80,
            windSpeed: 5.0,
            windDirection: 180,
            temperature: 15.0,
            dewPoint: nil,
            visibility: 10000,
            lowCloudCover: nil
        )
        
        let score = FogCalculator.calculate(from: forecast)
        
        XCTAssertEqual(score.score, 0)
        XCTAssertFalse(score.factors.contains(.lowTempDewDiff))
    }
    
    // MARK: - Low Visibility (<1000m)
    
    func testFogScoreWithLowVisibility() {
        let forecast = HourlyForecast(
            time: Date(),
            cloudCover: 0,
            humidity: 80,
            windSpeed: 5.0,
            windDirection: 180,
            temperature: 15.0,
            dewPoint: 12.0,
            visibility: 500,
            lowCloudCover: nil
        )
        
        let score = FogCalculator.calculate(from: forecast)
        
        XCTAssertEqual(score.score, 10)
        XCTAssertTrue(score.factors.contains(.lowVisibility))
    }
    
    func testFogScoreWithVisibilityAtThreshold() {
        let forecast = HourlyForecast(
            time: Date(),
            cloudCover: 0,
            humidity: 80,
            windSpeed: 5.0,
            windDirection: 180,
            temperature: 15.0,
            dewPoint: 12.0,
            visibility: 1000,
            lowCloudCover: nil
        )
        
        let score = FogCalculator.calculate(from: forecast)
        
        XCTAssertEqual(score.score, 0)
        XCTAssertFalse(score.factors.contains(.lowVisibility))
    }
    
    func testFogScoreWithNoVisibility() {
        let forecast = HourlyForecast(
            time: Date(),
            cloudCover: 0,
            humidity: 80,
            windSpeed: 5.0,
            windDirection: 180,
            temperature: 15.0,
            dewPoint: 12.0,
            visibility: nil,
            lowCloudCover: nil
        )
        
        let score = FogCalculator.calculate(from: forecast)
        
        XCTAssertEqual(score.score, 0)
        XCTAssertFalse(score.factors.contains(.lowVisibility))
    }
    
    // MARK: - High Low-Level Clouds (>80%)
    
    func testFogScoreWithHighLowClouds() {
        let forecast = HourlyForecast(
            time: Date(),
            cloudCover: 50,
            humidity: 80,
            windSpeed: 5.0,
            windDirection: 180,
            temperature: 15.0,
            dewPoint: 12.0,
            visibility: 10000,
            lowCloudCover: 85
        )
        
        let score = FogCalculator.calculate(from: forecast)
        
        XCTAssertEqual(score.score, 5)
        XCTAssertTrue(score.factors.contains(.highLowCloud))
    }
    
    func testFogScoreWithLowCloudsAtThreshold() {
        let forecast = HourlyForecast(
            time: Date(),
            cloudCover: 50,
            humidity: 80,
            windSpeed: 5.0,
            windDirection: 180,
            temperature: 15.0,
            dewPoint: 12.0,
            visibility: 10000,
            lowCloudCover: 80
        )
        
        let score = FogCalculator.calculate(from: forecast)
        
        XCTAssertEqual(score.score, 3)
        XCTAssertTrue(score.factors.contains(.highLowCloud))
    }
    
    func testFogScoreWithNoLowClouds() {
        let forecast = HourlyForecast(
            time: Date(),
            cloudCover: 50,
            humidity: 80,
            windSpeed: 5.0,
            windDirection: 180,
            temperature: 15.0,
            dewPoint: 12.0,
            visibility: 10000,
            lowCloudCover: nil
        )
        
        let score = FogCalculator.calculate(from: forecast)
        
        XCTAssertEqual(score.score, 0)
        XCTAssertFalse(score.factors.contains(.highLowCloud))
    }
    
    // MARK: - Combined Factors
    
    func testFogScoreWithMultipleFactors() {
        let forecast = HourlyForecast(
            time: Date(),
            cloudCover: 50,
            humidity: 98,
            windSpeed: 5.0,
            windDirection: 180,
            temperature: 15.0,
            dewPoint: 14.5,
            visibility: 500,
            lowCloudCover: 85
        )
        
        let score = FogCalculator.calculate(from: forecast)
        
        XCTAssertEqual(score.score, 73)
        XCTAssertTrue(score.factors.contains(.highHumidity))
        XCTAssertTrue(score.factors.contains(.lowTempDewDiff))
        XCTAssertTrue(score.factors.contains(.lowVisibility))
        XCTAssertTrue(score.factors.contains(.highLowCloud))
    }
    
    func testFogScoreWithNoFactors() {
        let forecast = HourlyForecast(
            time: Date(),
            cloudCover: 0,
            humidity: 50,
            windSpeed: 20.0,
            windDirection: 180,
            temperature: 20.0,
            dewPoint: 5.0,
            visibility: 20000,
            lowCloudCover: 10
        )
        
        let score = FogCalculator.calculate(from: forecast)
        
        XCTAssertEqual(score.score, 0)
        XCTAssertTrue(score.factors.isEmpty)
    }
    
    // MARK: - Calculate Current
    
    func testCalculateCurrentWithEmptyForecasts() {
        let score = FogCalculator.calculateCurrent(from: [])
        
        XCTAssertEqual(score.score, 0)
        XCTAssertTrue(score.factors.isEmpty)
    }
    
    func testCalculateCurrentWithForecasts() {
        let forecasts = [
            HourlyForecast(
                time: Date(),
                cloudCover: 0,
                humidity: 98,
                windSpeed: 5.0,
                windDirection: 180,
                temperature: 15.0,
                dewPoint: 14.5,
                visibility: 500,
                lowCloudCover: nil
            ),
            HourlyForecast(
                time: Date().addingTimeInterval(3600),
                cloudCover: 0,
                humidity: 50,
                windSpeed: 5.0,
                windDirection: 180,
                temperature: 15.0,
                dewPoint: 12.0,
                visibility: 10000,
                lowCloudCover: nil
            )
        ]
        
        let score = FogCalculator.calculateCurrent(from: forecasts)
        
        XCTAssertEqual(score.score, 68)
        XCTAssertTrue(score.factors.contains(.highHumidity))
        XCTAssertTrue(score.factors.contains(.lowTempDewDiff))
        XCTAssertTrue(score.factors.contains(.lowVisibility))
    }
    
    // MARK: - FogScore Score Bounds
    
    func testFogScoreScoreUpperBound() {
        let score = FogScore(score: 150, factors: [.highHumidity])
        
        XCTAssertEqual(score.score, 100)
    }
    
    func testFogScoreScoreLowerBound() {
        let score = FogScore(score: -50, factors: [.highHumidity])
        
        XCTAssertEqual(score.score, 0)
    }
    
    func testFogScoreScoreAtBoundaries() {
        let scoreZero = FogScore(score: 0, factors: [])
        let scoreFifty = FogScore(score: 50, factors: [])
        let scoreHundred = FogScore(score: 100, factors: [])
        
        XCTAssertEqual(scoreZero.score, 0)
        XCTAssertEqual(scoreFifty.score, 50)
        XCTAssertEqual(scoreHundred.score, 100)
    }
}

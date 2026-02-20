import XCTest
import Foundation
@testable import AstroViewingConditions

final class FormattersTests: XCTestCase {
    
    // MARK: - Date Formatters
    
    func testTimeFormatter() {
        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 19
        components.hour = 14
        components.minute = 30
        let date = Calendar.current.date(from: components)!
        
        let formatted = DateFormatters.formatTime(date)
        
        XCTAssertFalse(formatted.isEmpty)
    }
    
    func testShortDateFormatter() {
        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 19
        let date = Calendar.current.date(from: components)!
        
        let formatted = DateFormatters.formatShortDate(date)
        
        XCTAssertFalse(formatted.isEmpty)
        XCTAssertTrue(formatted.contains("Feb"))
    }
    
    func testFullDateFormatter() {
        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 19
        components.hour = 14
        components.minute = 30
        let date = Calendar.current.date(from: components)!
        
        let formatted = DateFormatters.formatFullDate(date)
        
        XCTAssertFalse(formatted.isEmpty)
    }
    
    func testTimeAgo() {
        let pastDate = Date().addingTimeInterval(-3600)
        
        let result = DateFormatters.timeAgo(from: pastDate)
        
        XCTAssertFalse(result.isEmpty)
    }
    
    // MARK: - Duration Formatting
    
    func testFormatDurationWithMinutesAndSeconds() {
        let duration: TimeInterval = 125 // 2m 5s
        
        let result = DateFormatters.formatDuration(duration)
        
        XCTAssertEqual(result, "2m 5s")
    }
    
    func testFormatDurationWithOnlySeconds() {
        let duration: TimeInterval = 45
        
        let result = DateFormatters.formatDuration(duration)
        
        XCTAssertEqual(result, "45s")
    }
    
    func testFormatDurationWithZero() {
        let duration: TimeInterval = 0
        
        let result = DateFormatters.formatDuration(duration)
        
        XCTAssertEqual(result, "0s")
    }
    
    func testFormatDurationWithLargeValue() {
        let duration: TimeInterval = 3665 // 1h 1m 5s
        
        let result = DateFormatters.formatDuration(duration)
        
        XCTAssertEqual(result, "61m 5s")
    }
    
    // MARK: - Coordinate Formatters
    
    func testFormatCoordinate() {
        let coordinate = Coordinate(latitude: 45.4627, longitude: -122.7491)
        
        let result = CoordinateFormatters.format(coordinate)
        
        XCTAssertTrue(result.contains("45.4627"))
        XCTAssertTrue(result.contains("122.7491"))
    }
    
    func testFormatLatitudePositive() {
        let result = CoordinateFormatters.formatLatitude(45.4627)
        
        XCTAssertTrue(result.contains("N"))
        XCTAssertTrue(result.contains("45.4627"))
    }
    
    func testFormatLatitudeNegative() {
        let result = CoordinateFormatters.formatLatitude(-45.4627)
        
        XCTAssertTrue(result.contains("S"))
        XCTAssertTrue(result.contains("45.4627"))
    }
    
    func testFormatLatitudeZero() {
        let result = CoordinateFormatters.formatLatitude(0)
        
        XCTAssertTrue(result.contains("0.0000"))
    }
    
    func testFormatLongitudePositive() {
        let result = CoordinateFormatters.formatLongitude(122.7491)
        
        XCTAssertTrue(result.contains("E"))
        XCTAssertTrue(result.contains("122.7491"))
    }
    
    func testFormatLongitudeNegative() {
        let result = CoordinateFormatters.formatLongitude(-122.7491)
        
        XCTAssertTrue(result.contains("W"))
        XCTAssertTrue(result.contains("122.7491"))
    }
    
    func testFormatLongitudeZero() {
        let result = CoordinateFormatters.formatLongitude(0)
        
        XCTAssertTrue(result.contains("0.0000"))
    }
    
    // MARK: - Edge Cases
    
    func testFormatTimeWithMidnight() {
        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 19
        components.hour = 0
        components.minute = 0
        let date = Calendar.current.date(from: components)!
        
        let formatted = DateFormatters.formatTime(date)
        
        XCTAssertFalse(formatted.isEmpty)
    }
    
    func testFormatTimeWith2359() {
        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 19
        components.hour = 23
        components.minute = 59
        let date = Calendar.current.date(from: components)!
        
        let formatted = DateFormatters.formatTime(date)
        
        XCTAssertFalse(formatted.isEmpty)
    }
}

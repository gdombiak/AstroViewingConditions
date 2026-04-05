import SharedCode
import XCTest
import Foundation
@testable import AstroViewingConditions

final class AstronomyServiceTests: XCTestCase {
    
    nonisolated(unsafe) var astronomyService: AstronomyService!
    
    override func setUp() async throws {
        try await super.setUp()
        astronomyService = AstronomyService()
    }
    
    // MARK: - Sun Events Tests
    
    func testCalculateSunEventsReturnsValidDates() async {
        let latitude = 45.4627
        let longitude = -122.7491
        let date = Date()
        
        let sunEvents = await astronomyService.calculateSunEvents(
            latitude: latitude,
            longitude: longitude,
            on: date
        )
        
        let calendar = Calendar.current
        
        XCTAssertFalse(sunEvents.sunrise == date, "sunrise should be calculated, not fallback")
        XCTAssertFalse(sunEvents.sunset == date, "sunset should be calculated, not fallback")
        XCTAssertFalse(sunEvents.civilTwilightBegin == date, "civilTwilightBegin should be calculated")
        XCTAssertFalse(sunEvents.civilTwilightEnd == date, "civilTwilightEnd should be calculated")
        XCTAssertFalse(sunEvents.nauticalTwilightBegin == date, "nauticalTwilightBegin should be calculated")
        XCTAssertFalse(sunEvents.nauticalTwilightEnd == date, "nauticalTwilightEnd should be calculated")
        XCTAssertFalse(sunEvents.astronomicalTwilightBegin == date, "astronomicalTwilightBegin should be calculated")
        XCTAssertFalse(sunEvents.astronomicalTwilightEnd == date, "astronomicalTwilightEnd should be calculated")
        
        let inputDay = calendar.startOfDay(for: date)
        let sunriseDay = calendar.startOfDay(for: sunEvents.sunrise)
        
        let daysDifference = calendar.dateComponents([.day], from: inputDay, to: sunriseDay).day ?? 0
        XCTAssertTrue(daysDifference >= 0 && daysDifference <= 1,
            "sunrise should be on input date or next day")
    }
    
    @MainActor
    func testViewModelSunEventsFormattedEndToEnd() async {
        let latitude = 45.4627
        let longitude = -122.7491
        let date = Date()
        
        let sunEvents = await astronomyService.calculateSunEvents(
            latitude: latitude,
            longitude: longitude,
            on: date
        )
        
        let location = CachedLocation(
            name: "Test",
            latitude: latitude,
            longitude: longitude,
            elevation: 100
        )
        
        let conditions = ViewingConditions(
            fetchedAt: date,
            location: location,
            hourlyForecasts: [],
            dailySunEvents: [sunEvents],
            dailyMoonInfo: [],
            issPasses: [],
            fogScore: FogScore(score: 0, factors: [])
        )
        
        let viewModel = DashboardViewModel()
        viewModel.viewingConditions = conditions
        viewModel.selectedDay = .today
        
        guard let currentSunEvents = viewModel.currentSunEvents else {
            XCTFail("ViewModel should have sun events")
            return
        }
        
        let formattedSunrise = DateFormatters.formatTime(currentSunEvents.sunrise)
        let formattedSunset = DateFormatters.formatTime(currentSunEvents.sunset)
        
        print("End-to-end: Sunrise: \(formattedSunrise), Sunset: \(formattedSunset)")
        
        XCTAssertFalse(formattedSunrise.isEmpty)
        XCTAssertFalse(formattedSunset.isEmpty)
        
        let calendar = Calendar.current
        let sunriseHour = calendar.component(.hour, from: currentSunEvents.sunrise)
        let sunsetHour = calendar.component(.hour, from: currentSunEvents.sunset)
        
        XCTAssertTrue(sunriseHour < sunsetHour,
            "In local time, sunrise should be before sunset. Got: \(formattedSunrise) -> \(formattedSunset)")
    }
    
    func testCalculateSunEventsWithSpecificLocation() async {
        let latitude = 40.7128  // New York
        let longitude = -74.0060
        let date = Date()
        
        let sunEvents = await astronomyService.calculateSunEvents(
            latitude: latitude,
            longitude: longitude,
            on: date
        )
        
        XCTAssertNotNil(sunEvents.sunrise)
        XCTAssertNotNil(sunEvents.sunset)
    }
    
    func testCalculateSunEventsTwilightOrder() async {
        let latitude = 45.4627
        let longitude = -122.7491
        let date = Date()
        
        let sunEvents = await astronomyService.calculateSunEvents(
            latitude: latitude,
            longitude: longitude,
            on: date
        )
        
        XCTAssertTrue(sunEvents.civilTwilightBegin <= sunEvents.sunrise)
        XCTAssertTrue(sunEvents.sunset <= sunEvents.civilTwilightEnd)
    }
    
    // MARK: - Moon Info Tests
    
    func testCalculateMoonInfoReturnsValidData() async {
        let latitude = 45.4627
        let longitude = -122.7491
        let date = Date()
        
        let moonInfo = await astronomyService.calculateMoonInfo(
            latitude: latitude,
            longitude: longitude,
            on: date
        )
        
        XCTAssertGreaterThanOrEqual(moonInfo.phase, 0)
        XCTAssertLessThanOrEqual(moonInfo.phase, 1)
        XCTAssertGreaterThanOrEqual(moonInfo.illumination, 0)
        XCTAssertLessThanOrEqual(moonInfo.illumination, 100)
        XCTAssertFalse(moonInfo.phaseName.isEmpty)
    }
    
    func testCalculateMoonInfoWithSpecificLocation() async {
        let latitude = 51.5074  // London
        let longitude = -0.1278
        let date = Date()
        
        let moonInfo = await astronomyService.calculateMoonInfo(
            latitude: latitude,
            longitude: longitude,
            on: date
        )
        
        XCTAssertNotNil(moonInfo.phaseName)
        XCTAssertNotNil(moonInfo.emoji)
    }
    
    // MARK: - Moon Phase Name Tests
    
    func testMoonPhaseNames() async {
        let latitude = 45.4627
        let longitude = -122.7491
        
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        
        // Test various dates to get different moon phases
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 1
        components.hour = 12
        
        var validPhases = Set<String>()
        
        for day in 0..<30 {
            components.day = day + 1
            if let date = calendar.date(from: components) {
                let moonInfo = await astronomyService.calculateMoonInfo(
                    latitude: latitude,
                    longitude: longitude,
                    on: date
                )
                validPhases.insert(moonInfo.phaseName)
            }
        }
        
        XCTAssertFalse(validPhases.isEmpty)
    }
    
    // MARK: - Edge Cases
    
    func testCalculateSunEventsAtEquator() async {
        let latitude = 0.0
        let longitude = 0.0
        let date = Date()
        
        let sunEvents = await astronomyService.calculateSunEvents(
            latitude: latitude,
            longitude: longitude,
            on: date
        )
        
        XCTAssertNotNil(sunEvents.sunrise)
        XCTAssertNotNil(sunEvents.sunset)
    }
    
    func testCalculateSunEventsAtNorthPole() async {
        let latitude = 89.0
        let longitude = 0.0
        let date = Date()
        
        let sunEvents = await astronomyService.calculateSunEvents(
            latitude: latitude,
            longitude: longitude,
            on: date
        )
        
        XCTAssertNotNil(sunEvents.sunrise)
        XCTAssertNotNil(sunEvents.sunset)
    }
    
    func testCalculateMoonInfoAltitudeRange() async {
        let latitude = 45.4627
        let longitude = -122.7491
        let date = Date()
        
        let moonInfo = await astronomyService.calculateMoonInfo(
            latitude: latitude,
            longitude: longitude,
            on: date
        )
        
        XCTAssertGreaterThanOrEqual(moonInfo.altitude, -90)
        XCTAssertLessThanOrEqual(moonInfo.altitude, 90)
    }
    
    // MARK: - Multiple Dates
    
    func testCalculateSunEventsForMultipleDays() async {
        let latitude = 45.4627
        let longitude = -122.7491
        let calendar = Calendar.current
        
        var previousSunset: Date?
        
        for dayOffset in 0..<7 {
            let date = calendar.date(byAdding: .day, value: dayOffset, to: Date())!
            
            let sunEvents = await astronomyService.calculateSunEvents(
                latitude: latitude,
                longitude: longitude,
                on: date
            )
            
            XCTAssertNotNil(sunEvents.sunset)
            
            if let previous = previousSunset {
                XCTAssertNotEqual(sunEvents.sunset, previous)
            }
            previousSunset = sunEvents.sunset
        }
    }
}

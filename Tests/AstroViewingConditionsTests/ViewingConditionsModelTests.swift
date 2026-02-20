import XCTest
import Foundation
@testable import AstroViewingConditions

final class ViewingConditionsModelTests: XCTestCase {
    
    // MARK: - ViewingConditions Codable
    
    func testViewingConditionsCodable() throws {
        let location = CachedLocation(
            name: "Test Location",
            latitude: 45.4627,
            longitude: -122.7491,
            elevation: 100
        )
        
        let forecasts = [
            HourlyForecast(
                time: Date(),
                cloudCover: 50,
                humidity: 80,
                windSpeed: 10.0,
                windDirection: 180,
                temperature: 15.0,
                dewPoint: 12.0,
                visibility: 10000,
                lowCloudCover: 30
            )
        ]
        
        let sunEvents = SunEvents(
            sunrise: Date(),
            sunset: Date().addingTimeInterval(43200),
            civilTwilightBegin: Date().addingTimeInterval(-1800),
            civilTwilightEnd: Date().addingTimeInterval(45000),
            nauticalTwilightBegin: Date().addingTimeInterval(-3600),
            nauticalTwilightEnd: Date().addingTimeInterval(46800),
            astronomicalTwilightBegin: Date().addingTimeInterval(-5400),
            astronomicalTwilightEnd: Date().addingTimeInterval(48600)
        )
        
        let moonInfo = MoonInfo(
            phase: 0.5,
            phaseName: "Full Moon",
            altitude: 45.0,
            illumination: 100,
            emoji: "🌕"
        )
        
        let issPasses = [
            ISSPass(
                riseTime: Date(),
                duration: 300,
                maxElevation: 45.0
            )
        ]
        
        let fogScore = FogScore(score: 25, factors: [.highHumidity])
        
        let conditions = ViewingConditions(
            fetchedAt: Date(),
            location: location,
            hourlyForecasts: forecasts,
            dailySunEvents: [sunEvents],
            dailyMoonInfo: [moonInfo],
            issPasses: issPasses,
            fogScore: fogScore
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(conditions)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ViewingConditions.self, from: data)
        
        XCTAssertEqual(decoded.location.name, "Test Location")
        XCTAssertEqual(decoded.hourlyForecasts.count, 1)
        XCTAssertEqual(decoded.dailySunEvents.count, 1)
        XCTAssertEqual(decoded.dailyMoonInfo.count, 1)
        XCTAssertEqual(decoded.issPasses.count, 1)
        XCTAssertEqual(decoded.fogScore.score, 25)
    }
    
    // MARK: - CachedLocation Codable
    
    func testCachedLocationCodable() throws {
        let location = CachedLocation(
            name: "Portland",
            latitude: 45.5152,
            longitude: -122.6784,
            elevation: 50.0
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(location)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CachedLocation.self, from: data)
        
        XCTAssertEqual(decoded.name, "Portland")
        XCTAssertEqual(decoded.latitude, 45.5152)
        XCTAssertEqual(decoded.longitude, -122.6784)
        XCTAssertEqual(decoded.elevation, 50.0)
    }
    
    func testCachedLocationCoordinate() {
        let location = CachedLocation(
            name: "Test",
            latitude: 45.0,
            longitude: -122.0,
            elevation: 100
        )
        
        let coordinate = location.coordinate
        
        XCTAssertEqual(coordinate.latitude, 45.0)
        XCTAssertEqual(coordinate.longitude, -122.0)
    }
    
    // MARK: - Coordinate Codable
    
    func testCoordinateCodable() throws {
        let coordinate = Coordinate(latitude: 45.4627, longitude: -122.7491)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(coordinate)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Coordinate.self, from: data)
        
        XCTAssertEqual(decoded.latitude, 45.4627)
        XCTAssertEqual(decoded.longitude, -122.7491)
    }
    
    // MARK: - HourlyForecast Codable
    
    func testHourlyForecastCodable() throws {
        let forecast = HourlyForecast(
            time: Date(),
            cloudCover: 75,
            humidity: 85,
            windSpeed: 15.5,
            windDirection: 270,
            temperature: 12.5,
            dewPoint: 10.0,
            visibility: 8000,
            lowCloudCover: 50
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(forecast)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(HourlyForecast.self, from: data)
        
        XCTAssertEqual(decoded.cloudCover, 75)
        XCTAssertEqual(decoded.humidity, 85)
        XCTAssertEqual(decoded.windSpeed, 15.5)
        XCTAssertEqual(decoded.windDirection, 270)
        XCTAssertEqual(decoded.temperature, 12.5)
    }
    
    func testHourlyForecastWithNilOptionals() throws {
        let forecast = HourlyForecast(
            time: Date(),
            cloudCover: 50,
            humidity: 70,
            windSpeed: 10.0,
            windDirection: 180,
            temperature: 15.0,
            dewPoint: nil,
            visibility: nil,
            lowCloudCover: nil
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(forecast)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(HourlyForecast.self, from: data)
        
        XCTAssertNil(decoded.dewPoint)
        XCTAssertNil(decoded.visibility)
        XCTAssertNil(decoded.lowCloudCover)
    }
    
    // MARK: - FogScore Codable
    
    func testFogScoreCodable() throws {
        let score = FogScore(score: 65, factors: [.highHumidity, .lowVisibility])
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(score)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(FogScore.self, from: data)
        
        XCTAssertEqual(decoded.score, 65)
        XCTAssertEqual(decoded.factors.count, 2)
    }
    
    // MARK: - SunEvents Codable
    
    func testSunEventsCodable() throws {
        let sunEvents = SunEvents(
            sunrise: Date(),
            sunset: Date().addingTimeInterval(43200),
            civilTwilightBegin: Date().addingTimeInterval(-1800),
            civilTwilightEnd: Date().addingTimeInterval(45000),
            nauticalTwilightBegin: Date().addingTimeInterval(-3600),
            nauticalTwilightEnd: Date().addingTimeInterval(46800),
            astronomicalTwilightBegin: Date().addingTimeInterval(-5400),
            astronomicalTwilightEnd: Date().addingTimeInterval(48600)
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(sunEvents)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SunEvents.self, from: data)
        
        XCTAssertNotNil(decoded.sunrise)
        XCTAssertNotNil(decoded.sunset)
    }
    
    // MARK: - MoonInfo Codable
    
    func testMoonInfoCodable() throws {
        let moonInfo = MoonInfo(
            phase: 0.25,
            phaseName: "First Quarter",
            altitude: 30.5,
            illumination: 50,
            emoji: "🌓"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(moonInfo)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MoonInfo.self, from: data)
        
        XCTAssertEqual(decoded.phaseName, "First Quarter")
        XCTAssertEqual(decoded.illumination, 50)
        XCTAssertEqual(decoded.emoji, "🌓")
    }
    
    // MARK: - ISSPass Codable
    
    func testISSPassCodable() throws {
        let pass = ISSPass(
            riseTime: Date(),
            duration: 300,
            maxElevation: 45.0
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(pass)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ISSPass.self, from: data)
        
        XCTAssertEqual(decoded.duration, 300)
        XCTAssertEqual(decoded.maxElevation, 45.0)
    }
    
    // MARK: - SunEvents Computed Properties
    
    func testAstronomicalNightDuration() {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 21
        let date = calendar.date(from: components)!
        
        let sunEvents = SunEvents(
            sunrise: calendar.date(bySettingHour: 5, minute: 30, second: 0, of: date)!,
            sunset: calendar.date(bySettingHour: 20, minute: 30, second: 0, of: date)!,
            civilTwilightBegin: calendar.date(bySettingHour: 5, minute: 0, second: 0, of: date)!,
            civilTwilightEnd: calendar.date(bySettingHour: 21, minute: 0, second: 0, of: date)!,
            nauticalTwilightBegin: calendar.date(bySettingHour: 4, minute: 15, second: 0, of: date)!,
            nauticalTwilightEnd: calendar.date(bySettingHour: 21, minute: 45, second: 0, of: date)!,
            astronomicalTwilightBegin: calendar.date(bySettingHour: 3, minute: 30, second: 0, of: date)!,
            astronomicalTwilightEnd: calendar.date(bySettingHour: 22, minute: 30, second: 0, of: date)!
        )
        
        let duration = sunEvents.astronomicalNightDuration(on: date)
        
        XCTAssertGreaterThan(duration, 0)
    }
}

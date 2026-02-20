import XCTest
import Foundation
@testable import AstroViewingConditions

final class WeatherServiceTests: XCTestCase {
    
    // MARK: - Test Data
    
    let mockOpenMeteoResponse = """
    {
      "utc_offset_seconds": -28800,
      "hourly": {
        "time": ["2026-02-19T00:00", "2026-02-19T01:00"],
        "cloudcover": [50, 75],
        "relativehumidity_2m": [80, 85],
        "windspeed_10m": [5.5, 6.2],
        "winddirection_10m": [180, 190],
        "temperature_2m": [12.5, 12.3],
        "dewpoint_2m": [8.5, 8.3],
        "precipitation": [0.0, 0.0],
        "visibility": [10000, 9500]
      }
    }
    """
    
    // MARK: - Parse Hourly Forecasts Tests
    
    func testParseHourlyForecastsSuccess() throws {
        let service = WeatherService()
        
        let data = mockOpenMeteoResponse.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(DateFormatter.apiDateFormatter)
        
        let response = try decoder.decode(OpenMeteoResponse.self, from: data)
        let forecasts = service.parseHourlyForecasts(from: response)
        
        XCTAssertEqual(forecasts.count, 2)
        XCTAssertEqual(forecasts[0].cloudCover, 50)
        XCTAssertEqual(forecasts[0].humidity, 80)
        XCTAssertEqual(forecasts[0].windSpeed, 5.5)
    }
    
    func testParseHourlyForecastsWithMissingFields() throws {
        let json = """
        {
          "utc_offset_seconds": -28800,
          "hourly": {
            "time": ["2026-02-19T00:00"],
            "cloudcover": [50],
            "relativehumidity_2m": [80],
            "windspeed_10m": [5.5],
            "winddirection_10m": [180],
            "temperature_2m": [12.5]
          }
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(DateFormatter.apiDateFormatter)
        
        let response = try decoder.decode(OpenMeteoResponse.self, from: data)
        let forecasts = WeatherService().parseHourlyForecasts(from: response)
        
        XCTAssertEqual(forecasts.count, 1)
        XCTAssertNil(forecasts[0].dewPoint)
        XCTAssertNil(forecasts[0].visibility)
    }
    
    func testParseHourlyForecastsNegativeValues() throws {
        let json = """
        {
          "utc_offset_seconds": 3600,
          "hourly": {
            "time": ["2026-02-19T00:00"],
            "cloudcover": [100],
            "relativehumidity_2m": [95],
            "windspeed_10m": [-5.0],
            "winddirection_10m": [270],
            "temperature_2m": [-10.5],
            "dewpoint_2m": [-12.0],
            "precipitation": [1.5],
            "visibility": [500]
          }
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(DateFormatter.apiDateFormatter)
        
        let response = try decoder.decode(OpenMeteoResponse.self, from: data)
        let forecasts = WeatherService().parseHourlyForecasts(from: response)
        
        XCTAssertEqual(forecasts[0].windSpeed, -5.0)
        XCTAssertEqual(forecasts[0].temperature, -10.5)
    }
    
    func testWeatherErrorCases() {
        XCTAssertTrue(WeatherError.invalidURL.localizedDescription.isEmpty == false)
        XCTAssertTrue(WeatherError.invalidResponse.localizedDescription.isEmpty == false)
        XCTAssertTrue(WeatherError.decodingError.localizedDescription.isEmpty == false)
    }
    
    func testOpenMeteoResponseDecoding() throws {
        let data = mockOpenMeteoResponse.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(DateFormatter.apiDateFormatter)
        
        let response = try decoder.decode(OpenMeteoResponse.self, from: data)
        
        XCTAssertEqual(response.utcOffsetSeconds, -28800)
        XCTAssertEqual(response.hourly.cloudcover.count, 2)
        XCTAssertEqual(response.hourly.relativehumidity2M.count, 2)
    }
    
    func testHourlyDataCodableKeys() throws {
        let json = """
        {
          "utc_offset_seconds": -28800,
          "hourly": {
            "time": ["2026-02-19T00:00"],
            "cloudcover": [50],
            "cloudcover_low": [30],
            "relativehumidity_2m": [80],
            "windspeed_10m": [5.5],
            "winddirection_10m": [180],
            "temperature_2m": [12.5],
            "dewpoint_2m": [8.5],
            "precipitation": [0.0],
            "visibility": [10000]
          }
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(DateFormatter.apiDateFormatter)
        
        let response = try decoder.decode(OpenMeteoResponse.self, from: data)
        
        XCTAssertEqual(response.hourly.cloudcoverLow?[0], 30)
    }
}

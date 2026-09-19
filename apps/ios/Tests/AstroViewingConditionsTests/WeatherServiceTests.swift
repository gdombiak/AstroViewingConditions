import SharedCode
import XCTest
import Foundation
@testable import AstroViewingConditions

final class WeatherServiceTests: XCTestCase {

    private func openMeteoFixture(_ name: String) throws -> Data {
        try Data(contentsOf: FixtureRoot.url("providers/open-meteo/forecast/\(name).json"))
    }

    private func decodeOpenMeteo(_ name: String) throws -> OpenMeteoResponse {
        try JSONDecoder().decode(OpenMeteoResponse.self, from: openMeteoFixture(name))
    }

    private func parseForecasts(_ name: String) throws -> [HourlyForecast] {
        WeatherService().parseHourlyForecasts(from: try decodeOpenMeteo(name))
    }

    private func utcInstant(_ iso: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return try XCTUnwrap(formatter.date(from: iso), iso)
    }

    // MARK: - Parse Hourly Forecasts Tests

    func testParseHourlyForecastsSuccess() throws {
        let service = WeatherService()
        let response = try decodeOpenMeteo("happy-path")
        let forecasts = service.parseHourlyForecasts(from: response)

        XCTAssertEqual(forecasts.count, 2)
        XCTAssertEqual(forecasts[0].cloudCover, 50)
        XCTAssertEqual(forecasts[0].humidity, 80)
        XCTAssertEqual(forecasts[0].windSpeed, 5.5)
        XCTAssertEqual(forecasts[0].windDirection, 180)
        XCTAssertEqual(forecasts[0].temperature, 12.5)
        XCTAssertEqual(forecasts[0].dewPoint, 8.5)
        XCTAssertEqual(forecasts[0].visibility, 10000)
        XCTAssertEqual(forecasts[0].time, try utcInstant("2026-02-19T08:00:00Z"))
        XCTAssertEqual(forecasts[1].cloudCover, 75)
        XCTAssertEqual(forecasts[1].humidity, 85)
        XCTAssertEqual(forecasts[1].windSpeed, 6.2)
        XCTAssertEqual(forecasts[1].windDirection, 190)
        XCTAssertEqual(forecasts[1].temperature, 12.3)
        XCTAssertEqual(forecasts[1].dewPoint, 8.3)
        XCTAssertEqual(forecasts[1].visibility, 9500)
        XCTAssertEqual(forecasts[1].time, try utcInstant("2026-02-19T09:00:00Z"))
        XCTAssertNil(response.timezone)
        XCTAssertEqual(response.utcOffsetSeconds, -28800)
    }

    func testParseHourlyForecastsWithMissingFields() throws {
        let forecasts = try parseForecasts("missing-fields")

        XCTAssertEqual(forecasts.count, 1)
        XCTAssertNil(forecasts[0].dewPoint)
        XCTAssertNil(forecasts[0].visibility)
        XCTAssertNil(forecasts[0].midCloudCover)
        XCTAssertNil(forecasts[0].highCloudCover)
        XCTAssertNil(forecasts[0].windSpeed200hPa)
    }

    func testParseHourlyForecastsNegativeValues() throws {
        let forecasts = try parseForecasts("negative-values")

        XCTAssertEqual(forecasts[0].windSpeed, -5.0)
        XCTAssertEqual(forecasts[0].temperature, -10.5)
    }

    func testParseHourlyForecastsTimezoneFromOffsetOnly() throws {
        let response = try decodeOpenMeteo("tz-from-offset-only")
        let forecasts = WeatherService().parseHourlyForecasts(from: response)

        XCTAssertNil(response.timezone)
        XCTAssertEqual(response.utcOffsetSeconds, -28800)
        XCTAssertEqual(forecasts.count, 2)
        XCTAssertEqual(forecasts[0].time, try utcInstant("2026-02-19T08:00:00Z"))
        XCTAssertEqual(forecasts[1].time, try utcInstant("2026-02-19T09:00:00Z"))
        XCTAssertEqual(forecasts[0].time.timeIntervalSince1970, 1_771_488_000)
        XCTAssertEqual(forecasts[1].time.timeIntervalSince1970, 1_771_491_600)
        XCTAssertEqual(forecasts[0].cloudCover, 50)
        XCTAssertEqual(forecasts[1].cloudCover, 75)
    }

    func testParseHourlyForecastsSkipsMalformedTimeWithoutShiftingArrays() throws {
        let response = try decodeOpenMeteo("malformed-time-skipped")
        let forecasts = WeatherService().parseHourlyForecasts(from: response)

        XCTAssertEqual(response.hourly.time.count, 3)
        XCTAssertEqual(forecasts.count, 2)

        XCTAssertEqual(forecasts[0].time, try utcInstant("2026-02-19T00:00:00Z"))
        XCTAssertEqual(forecasts[0].cloudCover, 10)
        XCTAssertEqual(forecasts[0].humidity, 11)
        XCTAssertEqual(forecasts[0].windSpeed, 1.5)
        XCTAssertEqual(forecasts[0].windDirection, 10)
        XCTAssertEqual(forecasts[0].temperature, 1.0)
        XCTAssertEqual(forecasts[0].dewPoint, 0.5)
        XCTAssertEqual(forecasts[0].visibility, 1000)

        XCTAssertEqual(forecasts[1].time, try utcInstant("2026-02-19T02:00:00Z"))
        XCTAssertEqual(forecasts[1].cloudCover, 30)
        XCTAssertEqual(forecasts[1].humidity, 31)
        XCTAssertEqual(forecasts[1].windSpeed, 3.5)
        XCTAssertEqual(forecasts[1].windDirection, 30)
        XCTAssertEqual(forecasts[1].temperature, 3.0)
        XCTAssertEqual(forecasts[1].dewPoint, 2.5)
        XCTAssertEqual(forecasts[1].visibility, 3000)
    }

    func testWeatherErrorCases() {
        XCTAssertTrue(WeatherError.invalidURL.localizedDescription.isEmpty == false)
        XCTAssertTrue(WeatherError.invalidResponse.localizedDescription.isEmpty == false)
        XCTAssertTrue(WeatherError.decodingError.localizedDescription.isEmpty == false)
    }

    func testFetchForecastTimesOutWhenLoaderNeverReturns() async {
        let service = WeatherService(forecastTimeout: 0.01) { _ in
            await withUnsafeContinuation { (_: UnsafeContinuation<Void, Never>) in }
            throw CancellationError()
        }

        do {
            _ = try await service.fetchForecast(latitude: 45, longitude: -122, days: 1)
            XCTFail("Expected timeout")
        } catch let error as WeatherError {
            guard case .timeout = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertEqual(error.localizedDescription, "Weather request timed out. Please try again.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAsyncTimeoutReturnsWithoutWaitingForUncooperativeOperation() async {
        let start = Date()
        do {
            let _: Void = try await AsyncTimeout.run(seconds: 0.01) {
                await withUnsafeContinuation { (_: UnsafeContinuation<Void, Never>) in }
            }
            XCTFail("Expected timeout")
        } catch is TimeoutError {
            XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testConditionsProviderKeepsWeatherWhenISSTimesOut() async throws {
        let weatherData = try openMeteoFixture("happy-path")
        let weather = WeatherService { url in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (weatherData, response)
        }
        let provider = ConditionsProvider(
            weatherService: weather,
            issServiceFactory: { apiKey in
                ISSService(apiKey: apiKey, timeout: 0.01) { _ in
                    await withUnsafeContinuation { (_: UnsafeContinuation<Void, Never>) in }
                    throw CancellationError()
                }
            }
        )

        let result = try await provider.fetchConditionsWithDiagnostics(
            for: CachedLocation(name: "Test", latitude: 45, longitude: -122),
            days: 1,
            apiKey: "key"
        )

        XCTAssertEqual(result.conditions.hourlyForecasts.count, 2)
        XCTAssertEqual(result.issError, .timeout)
        XCTAssertEqual(result.issFetchState, .failed(.timeout))
    }

    func testOpenMeteoResponseDecoding() throws {
        let response = try decodeOpenMeteo("happy-path")

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

        let response = try decoder.decode(OpenMeteoResponse.self, from: data)

        XCTAssertEqual(response.hourly.cloudcoverLow?[0], 30)
    }

    func testParseHourlyForecastsIncludesSeeingAndTransparencyFields() throws {
        let forecast = try XCTUnwrap(parseForecasts("layered-seeing-transparency").first)

        XCTAssertEqual(forecast.midCloudCover, 40)
        XCTAssertEqual(forecast.highCloudCover, 30)
        XCTAssertEqual(forecast.windSpeed200hPa, 120)
    }

    func testParseHourlyForecastsHandlesShortOptionalArrays() throws {
        let forecasts = try parseForecasts("short-optional-arrays")

        XCTAssertEqual(forecasts.count, 2)
        XCTAssertNil(forecasts[1].midCloudCover)
        XCTAssertNil(forecasts[1].highCloudCover)
        XCTAssertNil(forecasts[1].windSpeed200hPa)
    }
}

import XCTest
import Foundation
@testable import AstroViewingConditions

final class NetworkErrorTests: XCTestCase {
    
    private var mockSession: URLSession!
    
    override func setUp() {
        super.setUp()
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        mockSession = URLSession(configuration: config)
    }
    
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }
    
    // MARK: - HTTP 500 Server Error
    
    func testWeatherServiceHandlesServerError() async {
        let error = await testURLProtocolError(
            statusCode: 500,
            data: Data()
        )
        
        XCTAssertNotNil(error)
    }
    
    func testWeatherServiceHandlesHTTPError400() async {
        let error = await testURLProtocolError(
            statusCode: 400,
            data: Data()
        )
        
        XCTAssertNotNil(error)
    }
    
    func testWeatherServiceHandlesHTTPError404() async {
        let error = await testURLProtocolError(
            statusCode: 404,
            data: Data()
        )
        
        XCTAssertNotNil(error)
    }
    
    // MARK: - Network Timeout
    
    func testWeatherServiceHandlesTimeout() async {
        MockURLProtocol.requestHandler = { request in
            throw NSError(
                domain: NSURLErrorDomain,
                code: NSURLErrorTimedOut,
                userInfo: [NSLocalizedDescriptionKey: "Timed out"]
            )
        }
        
        let service = MockWeatherService(session: mockSession)
        
        do {
            _ = try await service.fetchForecast(latitude: 45.0, longitude: -122.0)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(true)
        }
    }
    
    // MARK: - No Network Connection
    
    func testWeatherServiceHandlesNoNetwork() async {
        MockURLProtocol.requestHandler = { request in
            throw NSError(
                domain: NSURLErrorDomain,
                code: NSURLErrorNotConnectedToInternet,
                userInfo: [NSLocalizedDescriptionKey: "No network connection"]
            )
        }
        
        let service = MockWeatherService(session: mockSession)
        
        do {
            _ = try await service.fetchForecast(latitude: 45.0, longitude: -122.0)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(true)
        }
    }
    
    // MARK: - Invalid JSON Response
    
    func testWeatherServiceHandlesInvalidJSON() async {
        let invalidJSON = "this is not valid json".data(using: .utf8)!
        
        MockURLProtocol.requestHandler = { request in
            return (HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!, invalidJSON)
        }
        
        let service = MockWeatherService(session: mockSession)
        
        do {
            _ = try await service.fetchForecast(latitude: 45.0, longitude: -122.0)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(true)
        }
    }
    
    // MARK: - Empty Response
    
    func testWeatherServiceHandlesEmptyResponse() async {
        MockURLProtocol.requestHandler = { request in
            return (HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!, Data())
        }
        
        let service = MockWeatherService(session: mockSession)
        
        do {
            _ = try await service.fetchForecast(latitude: 45.0, longitude: -122.0)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(true)
        }
    }
    
    // MARK: - Helper Methods
    
    private func testURLProtocolError(statusCode: Int, data: Data) async -> Error? {
        MockURLProtocol.requestHandler = { request in
            return (HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!, data)
        }
        
        let service = MockWeatherService(session: mockSession)
        
        do {
            _ = try await service.fetchForecast(latitude: 45.0, longitude: -122.0)
            return nil
        } catch {
            return error
        }
    }
}

// MARK: - Mock URLProtocol

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    
    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            let error = NSError(
                domain: "MockURLProtocol",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No request handler set"]
            )
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    
    override func stopLoading() {}
}

// MARK: - Mock WeatherService for Testing

actor MockWeatherService {
    private let session: URLSession
    private let baseURL = "https://api.open-meteo.com/v1/forecast"
    
    init(session: URLSession) {
        self.session = session
    }
    
    func fetchForecast(
        latitude: Double,
        longitude: Double,
        days: Int = 3
    ) async throws -> [HourlyForecast] {
        var components = URLComponents(string: baseURL)!
        
        let hourlyParams = [
            "cloudcover",
            "relativehumidity_2m",
            "windspeed_10m",
            "winddirection_10m",
            "temperature_2m"
        ].joined(separator: ",")
        
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "hourly", value: hourlyParams),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: String(days))
        ]
        
        guard let url = components.url else {
            throw WeatherError.invalidURL
        }
        
        do {
            let (data, response) = try await session.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw WeatherError.invalidResponse
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .formatted(DateFormatter.apiDateFormatter)
            let weatherResponse = try decoder.decode(OpenMeteoResponse.self, from: data)
            
            return parseHourlyForecasts(from: weatherResponse)
        } catch is DecodingError {
            throw WeatherError.decodingError
        }
    }
    
    private func parseHourlyForecasts(from response: OpenMeteoResponse) -> [HourlyForecast] {
        let hourly = response.hourly
        let utcOffsetSeconds = response.utcOffsetSeconds
        var forecasts: [HourlyForecast] = []
        
        for index in hourly.time.indices {
            let utcDate = hourly.time[index]
            let localDate = utcDate.addingTimeInterval(TimeInterval(-utcOffsetSeconds))
            
            let forecast = HourlyForecast(
                time: localDate,
                cloudCover: hourly.cloudcover[safe: index] ?? 0,
                humidity: hourly.relativehumidity2M[safe: index] ?? 0,
                windSpeed: hourly.windspeed10M[safe: index] ?? 0,
                windDirection: hourly.winddirection10M[safe: index] ?? 0,
                temperature: hourly.temperature2M[safe: index] ?? 0,
                dewPoint: hourly.dewpoint2M?[safe: index],
                visibility: hourly.visibility?[safe: index],
                lowCloudCover: hourly.cloudcoverLow?[safe: index]
            )
            forecasts.append(forecast)
        }
        
        return forecasts
    }
}

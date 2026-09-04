import Foundation
import os
import AstroEngine

private let weatherLogger = Logger(subsystem: "com.astroviewing.conditions", category: "WeatherService")

public protocol WeatherForecastProviding: Sendable {
    func fetchForecastForMultipleLocations(
        coordinates: [Coordinate],
        days: Int
    ) async throws -> [Coordinate: [HourlyForecast]]
}

public actor WeatherService: WeatherForecastProviding {
    private let baseURL = "https://api.open-meteo.com/v1/forecast"
    private let geocodingURL = "https://geocoding-api.open-meteo.com/v1/search"
    private static let hourlyParameters = [
        "cloudcover",
        "cloudcover_low",
        "cloud_cover_mid",
        "cloud_cover_high",
        "relativehumidity_2m",
        "windspeed_10m",
        "wind_speed_200hPa",
        "winddirection_10m",
        "temperature_2m",
        "dewpoint_2m",
        "precipitation",
        "visibility"
    ].joined(separator: ",")
    
    private let dataLoader: @Sendable (URL) async throws -> (Data, URLResponse)
    private let forecastTimeout: TimeInterval
    private let searchTimeout: TimeInterval
    private let batchTimeout: TimeInterval

    public init(
        forecastTimeout: TimeInterval = 15,
        searchTimeout: TimeInterval = 10,
        batchTimeout: TimeInterval = 20,
        dataLoader: @escaping @Sendable (URL) async throws -> (Data, URLResponse) = { url in
            try await URLSession.shared.data(from: url)
        }
    ) {
        self.forecastTimeout = forecastTimeout
        self.searchTimeout = searchTimeout
        self.batchTimeout = batchTimeout
        self.dataLoader = dataLoader
    }
    
    public func fetchForecast(
        latitude: Double,
        longitude: Double,
        days: Int
    ) async throws -> [HourlyForecast] {
        guard var components = URLComponents(string: baseURL) else {
            throw WeatherError.invalidURL
        }
        
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "hourly", value: Self.hourlyParameters),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: String(days))
        ]
        
        guard let url = components.url else {
            throw WeatherError.invalidURL
        }
        
        let (data, response) = try await weatherRequest(timeout: forecastTimeout) { [dataLoader] in
            try await dataLoader(url)
        }
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw WeatherError.invalidResponse
        }
        
        let decoder = JSONDecoder()
        let weatherResponse = try decoder.decode(OpenMeteoResponse.self, from: data)
        
        return parseHourlyForecasts(from: weatherResponse)
    }
    
    public func searchLocations(query: String) async throws -> [GeocodingResult] {
        guard var components = URLComponents(string: geocodingURL) else {
            throw WeatherError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "10"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json")
        ]
        
        guard let url = components.url else {
            throw WeatherError.invalidURL
        }
        
        let (data, response) = try await weatherRequest(timeout: searchTimeout) { [dataLoader] in
            try await dataLoader(url)
        }
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw WeatherError.invalidResponse
        }
        
        let decoder = JSONDecoder()
        let searchResponse = try decoder.decode(GeocodingResponse.self, from: data)
        
        return searchResponse.results ?? []
    }
    
    /// Fetches forecasts for multiple locations in batches
    /// Open-Meteo API has a limit on the number of locations per request
    public func fetchForecastForMultipleLocations(
        coordinates: [Coordinate],
        days: Int
    ) async throws -> [Coordinate: [HourlyForecast]] {
        guard !coordinates.isEmpty else {
            return [:]
        }
        
        return try await AsyncTimeout.run(
            seconds: batchTimeout,
            error: WeatherError.timeout
        ) { [self] in
            try await fetchForecastBatches(coordinates: coordinates, days: days)
        }
    }

    private func fetchForecastBatches(
        coordinates: [Coordinate],
        days: Int
    ) async throws -> [Coordinate: [HourlyForecast]] {
        // Open-Meteo API has a limit of ~50 locations per request
        let batchSize = 50
        var allResults: [Coordinate: [HourlyForecast]] = [:]
        
        // Process coordinates in batches
        for batchStart in stride(from: 0, to: coordinates.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, coordinates.count)
            let batch = Array(coordinates[batchStart..<batchEnd])
            
            let batchResults = try await fetchForecastBatch(
                coordinates: batch,
                days: days
            )
            
            allResults.merge(batchResults) { _, new in new }
            
            // Small delay between batches to avoid rate limiting
            if batchEnd < coordinates.count {
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
        }
        
        return allResults
    }
    
    /// Fetches forecasts for a single batch of locations
    private func fetchForecastBatch(
        coordinates: [Coordinate],
        days: Int
    ) async throws -> [Coordinate: [HourlyForecast]] {
        guard var components = URLComponents(string: baseURL) else {
            throw WeatherError.invalidURL
        }
        
        let latitudes = coordinates.map { String($0.latitude) }.joined(separator: ",")
        let longitudes = coordinates.map { String($0.longitude) }.joined(separator: ",")
        
        components.queryItems = [
            URLQueryItem(name: "latitude", value: latitudes),
            URLQueryItem(name: "longitude", value: longitudes),
            URLQueryItem(name: "hourly", value: Self.hourlyParameters),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: String(days))
        ]
        
        guard let url = components.url else {
            throw WeatherError.invalidURL
        }
        
        let (data, response) = try await dataLoader(url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw WeatherError.invalidResponse
        }
        
        let decoder = JSONDecoder()
        
        // Handle both single and multiple location responses
        if coordinates.count == 1 {
            let weatherResponse = try decoder.decode(OpenMeteoResponse.self, from: data)
            let forecasts = parseHourlyForecasts(from: weatherResponse)
            return [coordinates[0]: forecasts]
        } else {
            let weatherResponses = try decoder.decode([OpenMeteoResponse].self, from: data)
            var results: [Coordinate: [HourlyForecast]] = [:]
            
            for (index, response) in weatherResponses.enumerated() {
                guard index < coordinates.count else { break }
                let coordinate = coordinates[index]
                let forecasts = parseHourlyForecasts(from: response)
                results[coordinate] = forecasts
            }
            
            return results
        }
    }
    
    public nonisolated func parseHourlyForecasts(from response: OpenMeteoResponse) -> [HourlyForecast] {
        let parsed = OpenMeteoForecastDecoder.parseHourlyForecasts(from: response)
        if parsed.count < response.hourly.time.count {
            weatherLogger.warning("Skipped hourly forecast rows with malformed time")
        }
        return parsed
    }

    private func weatherRequest<T: Sendable>(
        timeout: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await AsyncTimeout.run(seconds: timeout, error: WeatherError.timeout, operation: operation)
    }
}

// MARK: - Errors

public enum WeatherError: Error, Sendable, LocalizedError {
    case invalidURL
    case invalidResponse
    case decodingError
    case timeout

    public var errorDescription: String? {
        switch self {
        case .timeout: return "Weather request timed out. Please try again."
        case .invalidURL: return "The weather service URL could not be created."
        case .invalidResponse: return "The weather service returned an invalid response."
        case .decodingError: return "The weather response could not be read."
        }
    }
}

public struct GeocodingResponse: Codable {
    public let results: [GeocodingResult]?
}

public struct GeocodingResult: Codable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public let elevation: Double?
    public let country: String?
    public let admin1: String? // State/Province
    
    public var displayName: String {
        if let admin1 = admin1, let country = country {
            return "\(name), \(admin1), \(country)"
        } else if let country = country {
            return "\(name), \(country)"
        } else {
            return name
        }
    }
}

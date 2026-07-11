import Foundation
import os

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
        let hourly = response.hourly
        let timeZone = response.timezone
            .flatMap(TimeZone.init(identifier:))
            ?? TimeZone(secondsFromGMT: response.utcOffsetSeconds)
            ?? TimeZone(secondsFromGMT: 0)
            ?? TimeZone.current
        let formatter = DateFormatter.openMeteoLocalDateFormatter(timeZone: timeZone)
        var forecasts: [HourlyForecast] = []
        
        for index in hourly.time.indices {
            guard let date = formatter.date(from: hourly.time[index]) else {
                weatherLogger.warning("Skipping hourly forecast with malformed time: \(hourly.time[index], privacy: .public)")
                continue
            }
            
            let forecast = HourlyForecast(
                time: date,
                cloudCover: hourly.cloudcover[safe: index] ?? 0,
                humidity: hourly.relativehumidity2M[safe: index] ?? 0,
                windSpeed: hourly.windspeed10M[safe: index] ?? 0,
                windDirection: hourly.winddirection10M[safe: index] ?? 0,
                temperature: hourly.temperature2M[safe: index] ?? 0,
                dewPoint: hourly.dewpoint2M?[safe: index],
                visibility: hourly.visibility?[safe: index],
                lowCloudCover: hourly.cloudcoverLow?[safe: index],
                midCloudCover: hourly.midCloudCover?[safe: index],
                highCloudCover: hourly.highCloudCover?[safe: index],
                windSpeed200hPa: hourly.windSpeed200hPa?[safe: index]
            )
            forecasts.append(forecast)
        }
        
        return forecasts
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

// MARK: - Open-Meteo Response Models

public struct OpenMeteoResponse: Codable {
    public let utcOffsetSeconds: Int
    public let timezone: String?
    public let hourly: HourlyData
    
    public enum CodingKeys: String, CodingKey {
        case utcOffsetSeconds = "utc_offset_seconds"
        case timezone
        case hourly
    }
    
    public init(utcOffsetSeconds: Int, timezone: String? = nil, hourly: HourlyData) {
        self.utcOffsetSeconds = utcOffsetSeconds
        self.timezone = timezone
        self.hourly = hourly
    }
}

public struct HourlyData: Codable {
    public let time: [String]
    public let cloudcover: [Int]
    public let cloudcoverLow: [Int]?
    public let midCloudCover: [Int]?
    public let highCloudCover: [Int]?
    public let relativehumidity2M: [Int]
    public let windspeed10M: [Double]
    public let winddirection10M: [Int]
    public let temperature2M: [Double]
    public let dewpoint2M: [Double]?
    public let precipitation: [Double]?
    public let visibility: [Double]?
    public let windSpeed200hPa: [Double]?
    
    public enum CodingKeys: String, CodingKey {
        case time
        case cloudcover
        case cloudcoverLow = "cloudcover_low"
        case midCloudCover = "cloud_cover_mid"
        case highCloudCover = "cloud_cover_high"
        case relativehumidity2M = "relativehumidity_2m"
        case windspeed10M = "windspeed_10m"
        case winddirection10M = "winddirection_10m"
        case temperature2M = "temperature_2m"
        case dewpoint2M = "dewpoint_2m"
        case precipitation
        case visibility
        case windSpeed200hPa = "wind_speed_200hPa"
    }
    
    public init(
        time: [String],
        cloudcover: [Int],
        cloudcoverLow: [Int]?,
        midCloudCover: [Int]? = nil,
        highCloudCover: [Int]? = nil,
        relativehumidity2M: [Int],
        windspeed10M: [Double],
        winddirection10M: [Int],
        temperature2M: [Double],
        dewpoint2M: [Double]?,
        precipitation: [Double]?,
        visibility: [Double]?,
        windSpeed200hPa: [Double]? = nil
    ) {
        self.time = time
        self.cloudcover = cloudcover
        self.cloudcoverLow = cloudcoverLow
        self.midCloudCover = midCloudCover
        self.highCloudCover = highCloudCover
        self.relativehumidity2M = relativehumidity2M
        self.windspeed10M = windspeed10M
        self.winddirection10M = winddirection10M
        self.temperature2M = temperature2M
        self.dewpoint2M = dewpoint2M
        self.precipitation = precipitation
        self.visibility = visibility
        self.windSpeed200hPa = windSpeed200hPa
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

// MARK: - Safe Array Access

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Date Decoding

extension JSONDecoder {
    static let iso8601: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension DateFormatter {
    public static func openMeteoLocalDateFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = timeZone
        return formatter
    }
}

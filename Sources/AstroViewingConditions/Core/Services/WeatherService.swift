import Foundation

public actor WeatherService {
    private let baseURL = "https://api.open-meteo.com/v1/forecast"
    private let geocodingURL = "https://geocoding-api.open-meteo.com/v1/search"
    
    public init() {}
    
    public func fetchForecast(
        latitude: Double,
        longitude: Double,
        days: Int = 3
    ) async throws -> [HourlyForecast] {
        var components = URLComponents(string: baseURL)!
        
        let hourlyParams = [
            "cloudcover",
            "cloudcover_low",
            "relativehumidity_2m",
            "windspeed_10m",
            "winddirection_10m",
            "temperature_2m",
            "dewpoint_2m",
            "precipitation",
            "visibility"
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
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw WeatherError.invalidResponse
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(DateFormatter.apiDateFormatter)
        let weatherResponse = try decoder.decode(OpenMeteoResponse.self, from: data)
        
        return parseHourlyForecasts(from: weatherResponse)
    }
    
    public func searchLocations(query: String) async throws -> [GeocodingResult] {
        var components = URLComponents(string: geocodingURL)!
        components.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "10"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json")
        ]
        
        guard let url = components.url else {
            throw WeatherError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw WeatherError.invalidResponse
        }
        
        let decoder = JSONDecoder()
        let searchResponse = try decoder.decode(GeocodingResponse.self, from: data)
        
        return searchResponse.results ?? []
    }
    
    private func parseHourlyForecasts(from response: OpenMeteoResponse) -> [HourlyForecast] {
        let hourly = response.hourly
        let utcOffsetSeconds = response.utcOffsetSeconds
        var forecasts: [HourlyForecast] = []
        
        for index in hourly.time.indices {
            // The API returns times without timezone info, but they represent local time
            // The DateFormatter parses them as UTC, so we need to apply the NEGATIVE offset
            // to shift from UTC back to the correct local time
            // Example: "2026-02-19T00:00" parsed as UTC is midnight UTC (8am LA time)
            // With offset -28800 (-8h), we subtract (-8h) = add 8h to get to midnight LA time
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

// MARK: - Errors

public enum WeatherError: Error {
    case invalidURL
    case invalidResponse
    case decodingError
}

// MARK: - Open-Meteo Response Models

struct OpenMeteoResponse: Codable {
    let utcOffsetSeconds: Int
    let hourly: HourlyData
    
    enum CodingKeys: String, CodingKey {
        case utcOffsetSeconds = "utc_offset_seconds"
        case hourly
    }
}

struct HourlyData: Codable {
    let time: [Date]
    let cloudcover: [Int]
    let cloudcoverLow: [Int]?
    let relativehumidity2M: [Int]
    let windspeed10M: [Double]
    let winddirection10M: [Int]
    let temperature2M: [Double]
    let dewpoint2M: [Double]?
    let precipitation: [Double]
    let visibility: [Double]?
    
    enum CodingKeys: String, CodingKey {
        case time
        case cloudcover
        case cloudcoverLow = "cloudcover_low"
        case relativehumidity2M = "relativehumidity_2m"
        case windspeed10M = "windspeed_10m"
        case winddirection10M = "winddirection_10m"
        case temperature2M = "temperature_2m"
        case dewpoint2M = "dewpoint_2m"
        case precipitation
        case visibility
    }
}

struct GeocodingResponse: Codable {
    let results: [GeocodingResult]?
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
    static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}

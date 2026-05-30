import Foundation
import CoreLocation

public actor ISSService {
    private let baseURL = "https://api.n2yo.com/rest/v1/satellite"
    private let issNoradId = 25544
    private let apiKey: String
    private static let apiKeyQueryValueAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=/?")
        return allowed
    }()
    
    public init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    public static func visualPassesURL(
        baseURL: String = "https://api.n2yo.com/rest/v1/satellite",
        noradId: Int = 25544,
        latitude: Double,
        longitude: Double,
        altitude: Double = 0,
        days: Int = 10,
        minVisibility: Int = 60,
        apiKey: String
    ) -> URL? {
        guard let encodedAPIKey = apiKey.addingPercentEncoding(withAllowedCharacters: apiKeyQueryValueAllowed) else {
            return nil
        }
        
        var components = URLComponents(string: baseURL)
        components?.path += "/visualpasses/\(noradId)/\(latitude)/\(longitude)/\(Int(altitude))/\(days)/\(minVisibility)/"
        components?.percentEncodedQuery = "apiKey=\(encodedAPIKey)"
        return components?.url
    }
    
    public func fetchPasses(
        latitude: Double,
        longitude: Double,
        altitude: Double = 0,
        days: Int = 10,
        minVisibility: Int = 60
    ) async throws -> [ISSPass] {
        // N2YO endpoint: /visualpasses/{id}/{observer_lat}/{observer_lng}/{observer_alt}/{days}/{min_visibility}/
        guard let url = Self.visualPassesURL(
            baseURL: baseURL,
            noradId: issNoradId,
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            days: days,
            minVisibility: minVisibility,
            apiKey: apiKey
        ) else {
            throw ISSError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ISSError.invalidResponse
        }
        
        let decoder = JSONDecoder()
        let issResponse = try decoder.decode(N2YOResponse.self, from: data)
        
        guard issResponse.passes != nil else {
            return []
        }
        
        return issResponse.passes?.map { pass in
            ISSPass(
                riseTime: Date(timeIntervalSince1970: TimeInterval(pass.startUTC)),
                duration: TimeInterval(pass.duration),
                maxElevation: pass.maxEl
            )
        } ?? []
    }
}

// MARK: - Errors

public enum ISSError: Error {
    case invalidURL
    case invalidResponse
    case apiError(String)
}

// MARK: - N2YO Response Models

public struct N2YOResponse: Codable {
    public let info: N2YOInfo
    public let passes: [N2YOPass]?
}

public struct N2YOInfo: Codable {
    public let satid: Int
    public let satname: String
    public let transactionscount: Int
    public let passescount: Int?
}

public struct N2YOPass: Codable {
    public let startAz: Double
    public let startAzCompass: String
    public let startEl: Double
    public let startUTC: Int
    public let maxAz: Double
    public let maxAzCompass: String
    public let maxEl: Double
    public let maxUTC: Int
    public let endAz: Double
    public let endAzCompass: String
    public let endEl: Double
    public let endUTC: Int
    public let mag: Double
    public let duration: Int
}

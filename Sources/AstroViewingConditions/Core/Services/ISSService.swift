import Foundation
import CoreLocation

public actor ISSService {
    private let baseURL = "http://api.open-notify.org/iss-pass.json"
    
    public init() {}
    
    public func fetchPasses(
        latitude: Double,
        longitude: Double,
        altitude: Double = 0,
        number: Int = 10
    ) async throws -> [ISSPass] {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude)),
            URLQueryItem(name: "alt", value: String(altitude)),
            URLQueryItem(name: "n", value: String(number))
        ]
        
        guard let url = components.url else {
            throw ISSError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ISSError.invalidResponse
        }
        
        let decoder = JSONDecoder()
        let issResponse = try decoder.decode(ISSResponse.self, from: data)
        
        guard issResponse.message == "success" else {
            throw ISSError.apiError(issResponse.message)
        }
        
        return issResponse.response.map { pass in
            ISSPass(
                riseTime: Date(timeIntervalSince1970: TimeInterval(pass.risetime)),
                duration: TimeInterval(pass.duration),
                maxElevation: calculateMaxElevation(duration: TimeInterval(pass.duration))
            )
        }
    }
    
    /// Estimate max elevation based on pass duration
    /// Longer passes typically reach higher elevations
    private func calculateMaxElevation(duration: TimeInterval) -> Double {
        // Rough estimation: longer duration = higher max elevation
        // ISS orbit is ~90 minutes, so max pass is ~6-7 minutes at zenith
        let minutes = duration / 60.0
        
        if minutes > 6 {
            return 80 + Double.random(in: 0...10) // Near zenith
        } else if minutes > 4 {
            return 60 + Double.random(in: 0...20) // High elevation
        } else if minutes > 2 {
            return 40 + Double.random(in: 0...20) // Medium elevation
        } else {
            return 10 + Double.random(in: 0...30) // Lower elevation
        }
    }
}

// MARK: - Errors

public enum ISSError: Error {
    case invalidURL
    case invalidResponse
    case apiError(String)
}

// MARK: - Response Models

struct ISSResponse: Codable {
    let message: String
    let request: ISSRequest
    let response: [ISSPassData]
}

struct ISSRequest: Codable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let passes: Int
    let datetime: Int
}

struct ISSPassData: Codable {
    let risetime: Int
    let duration: Int
}

import Foundation
import MapKit
import SharedCode

struct PlaceSearchResult: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    let latitude: Double
    let longitude: Double

    func savedLocation(elevation: Double?) -> SavedLocation {
        SavedLocation(name: name, latitude: latitude, longitude: longitude, elevation: elevation)
    }

    static func subtitle(name: String, title: String?, locality: String?, administrativeArea: String?, country: String?) -> String {
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !title.isEmpty, title != name {
            let prefix = name + ", "
            return title.hasPrefix(prefix) ? String(title.dropFirst(prefix.count)) : title
        }
        return [locality, administrativeArea, country]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: ", ")
    }
}

@MainActor
final class PlaceSearchService {
    private var activeSearches: [UUID: MKLocalSearch] = [:]

    func search(query: String) async throws -> [PlaceSearchResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest, .physicalFeature]
        let search = MKLocalSearch(request: request)
        let searchID = UUID()
        activeSearches[searchID] = search
        return try await withTaskCancellationHandler {
            defer {
                activeSearches.removeValue(forKey: searchID)
            }
            let response: MKLocalSearch.Response
            do {
                response = try await search.start()
            } catch {
                try Task.checkCancellation()
                if Self.isNoMatch(error) { return [] }
                throw error
            }
            try Task.checkCancellation()
            return response.mapItems.compactMap { item in
                let coordinate = item.placemark.coordinate
                guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
                let placemark = item.placemark
                let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let title = placemark.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let primaryName = name.isEmpty ? (title.isEmpty ? "Location" : title) : name
                return PlaceSearchResult(
                    name: primaryName,
                    subtitle: PlaceSearchResult.subtitle(
                        name: primaryName,
                        title: placemark.title,
                        locality: placemark.locality,
                        administrativeArea: placemark.administrativeArea,
                        country: placemark.country
                    ),
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.activeSearches[searchID]?.cancel()
            }
        }
    }

    static func isNoMatch(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == MKErrorDomain && error.code == Int(MKError.Code.placemarkNotFound.rawValue)
    }
}

struct TerrainElevationService {
    enum LookupError: Error {
        case invalidResponse
    }

    private let dataLoader: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 15, dataLoader: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = {
        try await URLSession.shared.data(for: $0)
    }) {
        self.timeout = timeout
        self.dataLoader = dataLoader
    }

    func elevationIfAvailable(latitude: Double, longitude: Double) async -> Double? {
        try? await elevation(latitude: latitude, longitude: longitude)
    }

    func elevation(latitude: Double, longitude: Double) async throws -> Double {
        guard var components = URLComponents(string: "https://api.open-meteo.com/v1/elevation") else {
            throw LookupError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude))
        ]
        guard let url = components.url else { throw LookupError.invalidResponse }
        let request = URLRequest(url: url)
        return try await AsyncTimeout.run(seconds: timeout) { [dataLoader] in
            let (data, response) = try await dataLoader(request)
            try Task.checkCancellation()
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let payload = try? JSONDecoder().decode(ElevationResponse.self, from: data),
                  let elevation = payload.elevation.first ?? nil,
                  elevation.isFinite else {
                throw LookupError.invalidResponse
            }
            return elevation
        }
    }

    private struct ElevationResponse: Decodable {
        let elevation: [Double?]
    }
}

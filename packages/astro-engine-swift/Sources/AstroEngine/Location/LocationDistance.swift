import Foundation
import CoreFoundation

public enum LocationDistance {
    public static let capabilityID = "location.distance"

    /// Shortest spherical arc in miles, using location.grid's Earth radius.
    public static func miles(from start: Coordinate, to end: Coordinate) -> Double {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let deltaLat = lat2 - lat1
        let deltaLon = (end.longitude - start.longitude) * .pi / 180
        let raw = pow(sin(deltaLat / 2), 2)
            + cos(lat1) * cos(lat2) * pow(sin(deltaLon / 2), 2)
        let haversine = min(1, max(0, raw))
        let angle = 2 * atan2(sqrt(haversine), sqrt(1 - haversine))
        return angle * GeographicGridGenerator.earthRadiusMeters
            / GeographicGridGenerator.metersPerMile
    }

    public static func evaluate(_ input: [String: Any]) throws -> [String: Any] {
        guard Set(input.keys) == ["from", "to"] else {
            throw LocationDistanceError.invalidInput
        }
        let start = try coordinate(input["from"])
        let end = try coordinate(input["to"])
        return ["distance_miles": miles(from: start, to: end)]
    }

    private static func coordinate(_ value: Any?) throws -> Coordinate {
        guard let row = value as? [String: Any],
              Set(row.keys) == ["latitude", "longitude"] else {
            throw LocationDistanceError.invalidInput
        }
        let latitude = try number(row["latitude"])
        let longitude = try number(row["longitude"])
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw LocationDistanceError.invalidInput
        }
        return Coordinate(latitude: latitude, longitude: longitude)
    }

    private static func number(_ value: Any?) throws -> Double {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else {
            throw LocationDistanceError.invalidInput
        }
        return number.doubleValue
    }
}

public enum LocationDistanceError: Error {
    case invalidInput
}

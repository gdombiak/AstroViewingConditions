import Foundation
import CoreLocation

public struct GridPoint: Sendable, Hashable {
    public let coordinate: Coordinate
    public let distanceMiles: Double
    public let bearing: Double
    public let elevation: Double?
    public let isCenter: Bool
    
    public init(
        coordinate: Coordinate,
        distanceMiles: Double,
        bearing: Double,
        elevation: Double? = nil,
        isCenter: Bool = false
    ) {
        self.coordinate = coordinate
        self.distanceMiles = distanceMiles
        self.bearing = bearing
        self.elevation = elevation
        self.isCenter = isCenter
    }
}

public struct GeographicGridGenerator {
    
    private static let metersPerMile: Double = 1609.344
    private static let earthRadiusMeters: Double = 6_371_000
    
    /// Generates a square grid clipped to a circular radius around a center location.
    /// - Parameters:
    ///   - center: The center coordinate
    ///   - radiusMiles: Search radius in miles (default: 30)
    ///   - spacingMiles: Distance between grid points in miles (default: 5)
    /// - Returns: Array of GridPoint with the center point first.
    public static func generateGrid(
        around center: Coordinate,
        radiusMiles: Double,
        spacingMiles: Double
    ) -> [GridPoint] {
        guard radiusMiles > 0, spacingMiles > 0 else { return [] }
        
        var points: [GridPoint] = []
        var seenCoordinates = Set<Coordinate>()

        func appendPoint(distanceMiles: Double, bearing: Double) {
            guard distanceMiles <= radiusMiles + 0.000_001 else { return }
            let coordinate = distanceMiles == 0
                ? center
                : coordinate(from: center, distanceMiles: distanceMiles, bearingDegrees: bearing)
            guard seenCoordinates.insert(coordinate).inserted else { return }
            points.append(GridPoint(
                coordinate: coordinate,
                distanceMiles: distanceMiles,
                bearing: bearing,
                elevation: nil,
                isCenter: distanceMiles == 0
            ))
        }

        points.append(GridPoint(
            coordinate: center,
            distanceMiles: 0,
            bearing: 0,
            elevation: nil,
            isCenter: true
        ))
        seenCoordinates.insert(center)

        let maxSteps = Int(floor(radiusMiles / spacingMiles))
        if maxSteps > 0 {
            for northSouthStep in (-maxSteps)...maxSteps {
                for eastWestStep in (-maxSteps)...maxSteps {
                    guard northSouthStep != 0 || eastWestStep != 0 else { continue }

                    let northMiles = Double(northSouthStep) * spacingMiles
                    let eastMiles = Double(eastWestStep) * spacingMiles
                    let distance = hypot(northMiles, eastMiles)
                    guard distance <= radiusMiles + 0.000_001 else { continue }

                    let bearing = normalizedBearing(degrees: atan2(eastMiles, northMiles) * 180 / .pi)
                    appendPoint(distanceMiles: distance, bearing: bearing)
                }
            }
        }

        for bearing in stride(from: 0.0, to: 360.0, by: 45.0) {
            appendPoint(distanceMiles: radiusMiles, bearing: bearing)
        }
        
        return points
    }

    public static func estimatedPointCount(radiusMiles: Double, spacingMiles: Double) -> Int {
        generateGrid(
            around: Coordinate(latitude: 0, longitude: 0),
            radiusMiles: radiusMiles,
            spacingMiles: spacingMiles
        ).count
    }
    
    /// Calculates the destination coordinate given a start point, distance, and bearing
    /// Uses the haversine formula for great-circle navigation
    private static func coordinate(
        from start: Coordinate,
        distanceMiles: Double,
        bearingDegrees: Double
    ) -> Coordinate {
        let distanceMeters = distanceMiles * metersPerMile
        let angularDistance = distanceMeters / earthRadiusMeters
        
        let lat1 = degreesToRadians(start.latitude)
        let lon1 = degreesToRadians(start.longitude)
        let bearing = degreesToRadians(bearingDegrees)
        
        let lat2 = asin(
            sin(lat1) * cos(angularDistance) +
            cos(lat1) * sin(angularDistance) * cos(bearing)
        )
        
        let lon2 = lon1 + atan2(
            sin(bearing) * sin(angularDistance) * cos(lat1),
            cos(angularDistance) - sin(lat1) * sin(lat2)
        )
        
        return Coordinate(
            latitude: radiansToDegrees(lat2),
            longitude: radiansToDegrees(lon2)
        )
    }
    
    private static func degreesToRadians(_ degrees: Double) -> Double {
        degrees * .pi / 180.0
    }
    
    private static func radiansToDegrees(_ radians: Double) -> Double {
        radians * 180.0 / .pi
    }

    private static func normalizedBearing(degrees: Double) -> Double {
        (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }
    
    /// Formats bearing as cardinal direction (N, NE, E, SE, S, SW, W, NW)
    public static func bearingToCardinal(_ bearing: Double) -> String {
        let normalizedBearing = (bearing.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((normalizedBearing + 11.25) / 22.5) % 16
        return directions[index]
    }
}

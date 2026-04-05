import Foundation
import CoreLocation

public struct GridPoint: Sendable, Hashable {
    public let coordinate: Coordinate
    public let distanceMiles: Double
    public let bearing: Double
    public let elevation: Double?
    
    public init(coordinate: Coordinate, distanceMiles: Double, bearing: Double, elevation: Double? = nil) {
        self.coordinate = coordinate
        self.distanceMiles = distanceMiles
        self.bearing = bearing
        self.elevation = elevation
    }
}

public struct GeographicGridGenerator {
    
    private static let metersPerMile: Double = 1609.344
    private static let earthRadiusMeters: Double = 6_371_000
    
    /// Generates a dynamic grid of points inside a radius around a center location
    /// - Parameters:
    ///   - center: The center coordinate
    ///   - radiusMiles: Search radius in miles (default: 30)
    ///   - spacingMiles: Distance between grid points in miles (default: 5)
    /// - Returns: Array of GridPoint, typically 40-70 points for 30mi/5mi spacing
    public static func generateGrid(
        around center: Coordinate,
        radiusMiles: Double,
        spacingMiles: Double
    ) -> [GridPoint] {
        guard radiusMiles > 0, spacingMiles > 0 else { return [] }
        
        var points: [GridPoint] = []
        
        // Always include center point
        points.append(GridPoint(
            coordinate: center,
            distanceMiles: 0,
            bearing: 0,
            elevation: nil
        ))
        
        // Generate concentric rings
        let numRings = Int(ceil(radiusMiles / spacingMiles))
        
        for ring in 1...numRings {
            let ringRadius = Double(ring) * spacingMiles
            
            // Number of points in this ring based on circumference
            // circumference = 2 * pi * radius, points every spacingMiles
            let circumference = 2 * .pi * ringRadius
            let numPointsInRing = max(6, Int(round(circumference / spacingMiles)))
            
            for i in 0..<numPointsInRing {
                let bearing = Double(i) * (360.0 / Double(numPointsInRing))
                
                let destCoordinate = coordinate(
                    from: center,
                    distanceMiles: ringRadius,
                    bearingDegrees: bearing
                )
                
                // Only include points within the radius (some hexagonal packing may exceed slightly)
                if ringRadius <= radiusMiles {
                    points.append(GridPoint(
                        coordinate: destCoordinate,
                        distanceMiles: ringRadius,
                        bearing: bearing,
                        elevation: nil
                    ))
                }
            }
        }
        
        return points
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
    
    /// Formats bearing as cardinal direction (N, NE, E, SE, S, SW, W, NW)
    public static func bearingToCardinal(_ bearing: Double) -> String {
        let normalizedBearing = (bearing.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((normalizedBearing + 11.25) / 22.5) % 16
        return directions[index]
    }
}

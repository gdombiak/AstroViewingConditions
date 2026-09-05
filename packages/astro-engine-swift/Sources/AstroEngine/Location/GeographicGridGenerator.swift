import Foundation

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

/// Contract DTO sample for `location.grid`. Production `GridPoint` stays unchanged.
public struct GeographicGridContractPoint: Sendable, Hashable {
    public let latitude: Double
    public let longitude: Double
    public let distanceMiles: Double
    public let bearingDegrees: Double
    public let isCenter: Bool
    public let northStep: Int?
    public let eastStep: Int?
}

public struct GeographicGridGenerator {
    
    private static let metersPerMile: Double = 1609.344
    private static let earthRadiusMeters: Double = 6_371_000
    /// 1.0 capability cap: result size of max iOS Best Nearby geometry (50 mi / 3 mi).
    public static let contractCapRadiusMiles: Double = 50
    public static let contractCapSpacingMiles: Double = 3
    public static let contractPointCapCount: Int = 885
    /// maxSteps >= 22 implies a 31×31 inscribed square (961 points) already over cap.
    private static let maxStepsExactCount: Int = 21
    
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
        generateContractGrid(
            around: center,
            radiusMiles: radiusMiles,
            spacingMiles: spacingMiles
        ).map { sample in
            GridPoint(
                coordinate: Coordinate(latitude: sample.latitude, longitude: sample.longitude),
                distanceMiles: sample.distanceMiles,
                bearing: sample.bearingDegrees,
                elevation: nil,
                isCenter: sample.isCenter
            )
        }
    }

    public static func generateContractGrid(
        around center: Coordinate,
        radiusMiles: Double,
        spacingMiles: Double
    ) -> [GeographicGridContractPoint] {
        guard radiusMiles > 0, spacingMiles > 0 else { return [] }
        
        var points: [GeographicGridContractPoint] = []
        var seenCoordinates = Set<Coordinate>()

        func appendPoint(
            distanceMiles: Double,
            bearing: Double,
            northStep: Int?,
            eastStep: Int?
        ) {
            guard distanceMiles <= radiusMiles + 0.000_001 else { return }
            let coordinate = distanceMiles == 0
                ? center
                : destination(from: center, distanceMiles: distanceMiles, bearingDegrees: bearing)
            guard seenCoordinates.insert(coordinate).inserted else { return }
            points.append(GeographicGridContractPoint(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                distanceMiles: distanceMiles,
                bearingDegrees: bearing,
                isCenter: distanceMiles == 0,
                northStep: northStep,
                eastStep: eastStep
            ))
        }

        points.append(GeographicGridContractPoint(
            latitude: center.latitude,
            longitude: center.longitude,
            distanceMiles: 0,
            bearingDegrees: 0,
            isCenter: true,
            northStep: 0,
            eastStep: 0
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
                    appendPoint(
                        distanceMiles: distance,
                        bearing: bearing,
                        northStep: northSouthStep,
                        eastStep: eastWestStep
                    )
                }
            }
        }

        for bearing in stride(from: 0.0, to: 360.0, by: 45.0) {
            appendPoint(
                distanceMiles: radiusMiles,
                bearing: bearing,
                northStep: nil,
                eastStep: nil
            )
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

    public static func contractPointCap() -> Int {
        contractPointCapCount
    }

    /// Capability preflight. True when a positive geometry would exceed 885 points.
    ///
    /// Bounded work: integer-lattice hypot only. Does not allocate destinations.
    /// Non-positive radius/spacing is not a cap (those yield an empty grid).
    public static func exceedsContractPointCap(radiusMiles: Double, spacingMiles: Double) -> Bool {
        guard radiusMiles > 0, spacingMiles > 0 else { return false }
        let ratio = radiusMiles / spacingMiles
        guard ratio.isFinite, ratio < Double(maxStepsExactCount + 1) else { return true }
        let maxSteps = Int(ratio.rounded(.down))
        return boundedPointCount(
            radiusMiles: radiusMiles,
            spacingMiles: spacingMiles,
            maxSteps: maxSteps
        ) > contractPointCapCount
    }

    private static func boundedPointCount(
        radiusMiles: Double,
        spacingMiles: Double,
        maxSteps: Int
    ) -> Int {
        var count = 1
        var occupiedBoundary = 0
        if maxSteps > 0 {
            for northSouthStep in (-maxSteps)...maxSteps {
                for eastWestStep in (-maxSteps)...maxSteps {
                    guard northSouthStep != 0 || eastWestStep != 0 else { continue }
                    let distance = hypot(
                        Double(northSouthStep) * spacingMiles,
                        Double(eastWestStep) * spacingMiles
                    )
                    guard distance <= radiusMiles + 0.000_001 else { continue }
                    count += 1
                    if distance == radiusMiles, let bit = compass8Bit(north: northSouthStep, east: eastWestStep) {
                        occupiedBoundary |= 1 << bit
                    }
                }
            }
        }
        for bit in 0..<8 {
            if occupiedBoundary & (1 << bit) == 0 {
                count += 1
            }
        }
        return count
    }

    private static func compass8Bit(north: Int, east: Int) -> Int? {
        if north != 0, east != 0, abs(north) != abs(east) {
            return nil
        }
        let n = north == 0 ? 0 : (north > 0 ? 1 : -1)
        let e = east == 0 ? 0 : (east > 0 ? 1 : -1)
        switch (n, e) {
        case (1, 0): return 0
        case (1, 1): return 1
        case (0, 1): return 2
        case (-1, 1): return 3
        case (-1, 0): return 4
        case (-1, -1): return 5
        case (0, -1): return 6
        case (1, -1): return 7
        default: return nil
        }
    }
    
    /// Calculates the destination coordinate given a start point, distance, and bearing
    /// Uses the haversine formula for great-circle navigation
    private static func destination(
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

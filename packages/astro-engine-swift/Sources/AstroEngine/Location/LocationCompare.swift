import Foundation

/// Four suitability states that participate in Best Nearby ranking.
///
/// Host geocoding reasons and English unsuitable copy stay outside the engine.
/// Ranks match `LocationSuitabilityStatus.verificationRank`.
public enum LocationCompareSuitability: String, Sendable, Hashable, CaseIterable {
    case suitable
    case unknown
    case unchecked
    case unsuitable

    public var verificationRank: Int {
        switch self {
        case .suitable:
            return 0
        case .unknown:
            return 1
        case .unchecked:
            return 2
        case .unsuitable:
            return 3
        }
    }
}

public struct LocationCompareError: Error, Equatable, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }
}

/// Portable Best Nearby candidate. Identity is `key`, not a host UUID.
public struct LocationCompareCandidate: Sendable, Hashable {
    public var key: String
    public var publicScore: Int
    public var nightConditionsScore: Int
    public var avgCloudCover: Double
    public var fogScore: Int
    public var avgWindSpeed: Double
    public var distanceMiles: Double
    public var latitude: Double
    public var longitude: Double
    public var suitability: LocationCompareSuitability

    public init(
        key: String,
        publicScore: Int,
        nightConditionsScore: Int,
        avgCloudCover: Double,
        fogScore: Int,
        avgWindSpeed: Double,
        distanceMiles: Double,
        latitude: Double,
        longitude: Double,
        suitability: LocationCompareSuitability = .unchecked
    ) {
        self.key = key
        self.publicScore = publicScore
        self.nightConditionsScore = nightConditionsScore
        self.avgCloudCover = avgCloudCover
        self.fogScore = fogScore
        self.avgWindSpeed = avgWindSpeed
        self.distanceMiles = distanceMiles
        self.latitude = latitude
        self.longitude = longitude
        self.suitability = suitability
    }
}

/// Deterministic `location.compare`: production Best Nearby total order plus a
/// contract-only `key` tie-breaker. Does not geocode, fetch weather, or build grids.
public enum LocationCompare {
    public static let capabilityID = "location.compare"

    /// Production `BestSpotSearcher.isHigherRanked` keys, without candidate identity.
    public static func isHigherRanked(_ lhs: LocationScore, than rhs: LocationScore) -> Bool {
        isHigherRanked(
            publicScore: (lhs.score, rhs.score),
            avgCloudCover: (lhs.avgCloudCover, rhs.avgCloudCover),
            fogScore: (lhs.fogScore.score, rhs.fogScore.score),
            avgWindSpeed: (lhs.avgWindSpeed, rhs.avgWindSpeed),
            verificationRank: (lhs.suitability.verificationRank, rhs.suitability.verificationRank),
            distanceMiles: (lhs.point.distanceMiles, rhs.point.distanceMiles),
            latitude: (lhs.point.coordinate.latitude, rhs.point.coordinate.latitude),
            longitude: (lhs.point.coordinate.longitude, rhs.point.coordinate.longitude)
        )
    }

    public static func isHigherRanked(
        _ lhs: LocationCompareCandidate,
        than rhs: LocationCompareCandidate
    ) -> Bool {
        if let decided = productionDecision(
            publicScore: (lhs.publicScore, rhs.publicScore),
            avgCloudCover: (lhs.avgCloudCover, rhs.avgCloudCover),
            fogScore: (lhs.fogScore, rhs.fogScore),
            avgWindSpeed: (lhs.avgWindSpeed, rhs.avgWindSpeed),
            verificationRank: (lhs.suitability.verificationRank, rhs.suitability.verificationRank),
            distanceMiles: (lhs.distanceMiles, rhs.distanceMiles),
            latitude: (lhs.latitude, rhs.latitude),
            longitude: (lhs.longitude, rhs.longitude)
        ) {
            return decided
        }
        return keyIsLess(lhs.key, than: rhs.key)
    }

    /// Lexicographic UTF-8 byte order. Not Unicode collation, not locale, not
    /// Swift canonical equivalence. Contract-only; unused by `LocationScore`.
    public static func keyIsLess(_ lhs: String, than rhs: String) -> Bool {
        lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
    }

    static func utf8Bytes(_ value: String) -> [UInt8] {
        Array(value.utf8)
    }

    public static func compare(
        _ candidates: [LocationCompareCandidate]
    ) throws -> [LocationCompareCandidate] {
        var seen = Set<[UInt8]>()
        for candidate in candidates {
            if candidate.key.isEmpty {
                throw LocationCompareError("candidate key is required")
            }
            if !seen.insert(utf8Bytes(candidate.key)).inserted {
                throw LocationCompareError("duplicate candidate key: \(candidate.key)")
            }
        }
        return candidates.sorted { lhs, rhs in isHigherRanked(lhs, than: rhs) }
    }

    public static func evaluate(injected: [String: Any]) throws -> [String: Any] {
        let ranked = try decodeAndRank(injected)
        return [
            "ranking": ranked.map(\.key),
            "locations": ranked.map(encode),
        ]
    }

    static func isHigherRanked(
        publicScore: (Int, Int),
        avgCloudCover: (Double, Double),
        fogScore: (Int, Int),
        avgWindSpeed: (Double, Double),
        verificationRank: (Int, Int),
        distanceMiles: (Double, Double),
        latitude: (Double, Double),
        longitude: (Double, Double)
    ) -> Bool {
        productionDecision(
            publicScore: publicScore,
            avgCloudCover: avgCloudCover,
            fogScore: fogScore,
            avgWindSpeed: avgWindSpeed,
            verificationRank: verificationRank,
            distanceMiles: distanceMiles,
            latitude: latitude,
            longitude: longitude
        ) ?? (longitude.0 < longitude.1)
    }

    private static func productionDecision(
        publicScore: (Int, Int),
        avgCloudCover: (Double, Double),
        fogScore: (Int, Int),
        avgWindSpeed: (Double, Double),
        verificationRank: (Int, Int),
        distanceMiles: (Double, Double),
        latitude: (Double, Double),
        longitude: (Double, Double)
    ) -> Bool? {
        if publicScore.0 != publicScore.1 { return publicScore.0 > publicScore.1 }
        if avgCloudCover.0 != avgCloudCover.1 { return avgCloudCover.0 < avgCloudCover.1 }
        if fogScore.0 != fogScore.1 { return fogScore.0 < fogScore.1 }
        if avgWindSpeed.0 != avgWindSpeed.1 { return avgWindSpeed.0 < avgWindSpeed.1 }
        if verificationRank.0 != verificationRank.1 { return verificationRank.0 < verificationRank.1 }
        if distanceMiles.0 != distanceMiles.1 { return distanceMiles.0 < distanceMiles.1 }
        if latitude.0 != latitude.1 { return latitude.0 < latitude.1 }
        if longitude.0 != longitude.1 { return longitude.0 < longitude.1 }
        return nil
    }

    private static func decodeAndRank(_ injected: [String: Any]) throws -> [LocationCompareCandidate] {
        guard let rows = injected["candidates"] as? [Any] else {
            throw LocationCompareError("injected.candidates must be an array")
        }
        let overlay = try decodeOverlay(injected["suitability"])
        var candidates: [LocationCompareCandidate] = []
        var seen = Set<[UInt8]>()
        candidates.reserveCapacity(rows.count)
        for row in rows {
            guard let object = row as? [String: Any] else {
                throw LocationCompareError("candidates must be objects")
            }
            let key = try decodeKey(object["key"])
            let keyBytes = utf8Bytes(key)
            if !seen.insert(keyBytes).inserted {
                throw LocationCompareError("duplicate candidate key: \(key)")
            }
            let publicScore = try requireInt(object["public_score"], name: "public_score")
            let nightScore = try requireInt(
                object["night_conditions_score"],
                name: "night_conditions_score"
            )
            var candidate = LocationCompareCandidate(
                key: key,
                publicScore: publicScore,
                nightConditionsScore: nightScore,
                avgCloudCover: try requireDouble(object["avg_cloud_cover"], name: "avg_cloud_cover"),
                fogScore: try requireInt(object["fog_score"], name: "fog_score"),
                avgWindSpeed: try requireDouble(object["avg_wind_speed"], name: "avg_wind_speed"),
                distanceMiles: try requireDouble(object["distance_miles"], name: "distance_miles"),
                latitude: try requireDouble(object["latitude"], name: "latitude"),
                longitude: try requireDouble(object["longitude"], name: "longitude")
            )
            if let status = overlay[keyBytes] {
                candidate.suitability = status
            }
            candidates.append(candidate)
        }
        for (overlayBytes, _) in overlay where !seen.contains(overlayBytes) {
            let label = String(decoding: overlayBytes, as: UTF8.self)
            throw LocationCompareError("unknown suitability key: \(label)")
        }
        return try compare(candidates)
    }

    private static func decodeOverlay(_ value: Any?) throws -> [[UInt8]: LocationCompareSuitability] {
        guard let value else { return [:] }
        guard let rows = value as? [Any] else {
            throw LocationCompareError("suitability must be an array")
        }
        var overlay: [[UInt8]: LocationCompareSuitability] = [:]
        for row in rows {
            guard let object = row as? [String: Any] else {
                throw LocationCompareError("suitability entries must be objects")
            }
            let key = try decodeKey(object["key"])
            guard let token = object["suitability"] as? String,
                  let status = LocationCompareSuitability(rawValue: token) else {
                throw LocationCompareError(
                    "suitability value must be suitable, unknown, unchecked, or unsuitable"
                )
            }
            let bytes = utf8Bytes(key)
            if overlay[bytes] != nil {
                throw LocationCompareError("duplicate candidate key: \(key)")
            }
            overlay[bytes] = status
        }
        return overlay
    }

    private static func decodeKey(_ value: Any?) throws -> String {
        guard let key = value as? String, !key.isEmpty else {
            throw LocationCompareError("candidate key is required")
        }
        return key
    }

    private static func encode(_ candidate: LocationCompareCandidate) -> [String: Any] {
        [
            "key": candidate.key,
            "public_score": candidate.publicScore,
            "night_conditions_score": candidate.nightConditionsScore,
            "avg_cloud_cover": candidate.avgCloudCover,
            "fog_score": candidate.fogScore,
            "avg_wind_speed": candidate.avgWindSpeed,
            "suitability": candidate.suitability.rawValue,
            "distance_miles": candidate.distanceMiles,
            "latitude": candidate.latitude,
            "longitude": candidate.longitude,
        ]
    }

    private static func requireDouble(_ value: Any?, name: String) throws -> Double {
        guard let number = jsonDouble(value) else {
            throw LocationCompareError("\(name) must be a finite JSON number")
        }
        return number
    }

    private static func requireInt(_ value: Any?, name: String) throws -> Int {
        guard let number = jsonDouble(value) else {
            throw LocationCompareError("\(name) must be a finite JSON number")
        }
        guard number.rounded(.towardZero) == number else {
            throw LocationCompareError("\(name) must be an integral number")
        }
        let asInt = Int(number)
        guard Double(asInt) == number else {
            throw LocationCompareError("\(name) must be an integral number")
        }
        return asInt
    }
}

private func jsonDouble(_ value: Any?) -> Double? {
    if value is NSNull { return nil }
    if let number = value as? NSNumber {
        if CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() { return nil }
        let doubleValue = number.doubleValue
        return doubleValue.isFinite ? doubleValue : nil
    }
    if let number = value as? Double { return number.isFinite ? number : nil }
    if let number = value as? Int { return Double(number) }
    return nil
}

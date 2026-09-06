import XCTest
import Foundation
@testable import AstroEngine

final class LocationCompareTests: XCTestCase {
    func testSuitabilityRanksMatchLocationSuitabilityStatus() {
        XCTAssertEqual(
            LocationCompareSuitability.suitable.verificationRank,
            LocationSuitabilityStatus.suitable.verificationRank
        )
        XCTAssertEqual(
            LocationCompareSuitability.unknown.verificationRank,
            LocationSuitabilityStatus.unknown(reason: .notChecked).verificationRank
        )
        XCTAssertEqual(
            LocationCompareSuitability.unknown.verificationRank,
            LocationSuitabilityStatus.unknown(reason: .geocodingFailed).verificationRank
        )
        XCTAssertEqual(
            LocationCompareSuitability.unknown.verificationRank,
            LocationSuitabilityStatus.unknown(reason: .temporarilyUnavailable).verificationRank
        )
        XCTAssertEqual(
            LocationCompareSuitability.unchecked.verificationRank,
            LocationSuitabilityStatus.unchecked.verificationRank
        )
        XCTAssertEqual(
            LocationCompareSuitability.unsuitable.verificationRank,
            LocationSuitabilityStatus.unsuitable(reason: "Water area").verificationRank
        )
        XCTAssertEqual(
            LocationCompareSuitability.allCases.map(\.verificationRank),
            [0, 1, 2, 3]
        )
    }

    func testLocationScoreRankingIgnoresCandidateKey() throws {
        let left = try locationScore(
            score: 80,
            cloud: 10,
            fog: 10,
            wind: 10,
            suitability: .unchecked,
            distance: 5,
            latitude: 40,
            longitude: -74
        )
        let right = try locationScore(
            score: 80,
            cloud: 10,
            fog: 10,
            wind: 10,
            suitability: .unchecked,
            distance: 5,
            latitude: 40,
            longitude: -74
        )
        XCTAssertFalse(LocationCompare.isHigherRanked(left, than: right))
        XCTAssertFalse(LocationCompare.isHigherRanked(right, than: left))
        XCTAssertFalse(LocationCompare.isHigherRanked(left, than: left))
    }

    func testLocationScoreRankingUsesProductionKeys() throws {
        let suitable = try locationScore(
            score: 90,
            suitability: .suitable,
            longitude: -74
        )
        let unknown = try locationScore(
            score: 90,
            suitability: .unknown(reason: .notChecked),
            longitude: -74
        )
        XCTAssertTrue(LocationCompare.isHigherRanked(suitable, than: unknown))
        XCTAssertFalse(LocationCompare.isHigherRanked(unknown, than: suitable))
    }

    func testContractKeyBreaksProductionTies() throws {
        let left = candidate(key: "b")
        let right = candidate(key: "a")
        XCTAssertTrue(LocationCompare.isHigherRanked(right, than: left))
        XCTAssertFalse(LocationCompare.isHigherRanked(left, than: right))
        let ranked = try LocationCompare.compare([left, right])
        XCTAssertEqual(ranked.map(\.key), ["a", "b"])
    }

    func testNamedContractFixtures() throws {
        let root = try ContractsRoot.resolve()
        let directory = root.appendingPathComponent("fixtures/capabilities/location-compare")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { !$0.hasPrefix(".") }
            .sorted()
        XCTAssertEqual(names, [
            "default-unchecked-v1",
            "duplicate-key-v1",
            "invalid-suitability-v1",
            "missing-night-conditions-score-v1",
            "public-score-wins-v1",
            "successive-tie-breaks-v1",
            "suitability-injected-v1",
            "unknown-suitability-key-v1",
            "utf8-key-order-v1",
            "utf8-suitability-overlay-v1",
        ])
        for name in names {
            let fixture = directory.appendingPathComponent(name)
            let input = try jsonObject(fixture.appendingPathComponent("input.json"))
            let expected = try jsonObject(fixture.appendingPathComponent("expected.json"))
            let injected = try XCTUnwrap(input["injected"] as? [String: Any])
            if expected["ok"] as? Bool == true {
                let actual = try LocationCompare.evaluate(injected: injected)
                let expectedResult = try XCTUnwrap(expected["result"] as? [String: Any])
                XCTAssertEqual(
                    actual["ranking"] as? [String],
                    expectedResult["ranking"] as? [String],
                    name
                )
                let actualLocations = try XCTUnwrap(actual["locations"] as? [[String: Any]])
                let expectedLocations = try XCTUnwrap(expectedResult["locations"] as? [[String: Any]])
                XCTAssertEqual(actualLocations.count, expectedLocations.count, name)
                for (index, (actualRow, expectedRow)) in zip(actualLocations, expectedLocations).enumerated() {
                    XCTAssertEqual(actualRow["key"] as? String, expectedRow["key"] as? String, "\(name)[\(index)]")
                    XCTAssertEqual(actualRow["suitability"] as? String, expectedRow["suitability"] as? String, "\(name)[\(index)]")
                    XCTAssertEqual(actualRow["public_score"] as? Int, expectedRow["public_score"] as? Int, "\(name)[\(index)]")
                    XCTAssertEqual(actualRow["fog_score"] as? Int, expectedRow["fog_score"] as? Int, "\(name)[\(index)]")
                }
            } else {
                XCTAssertThrowsError(try LocationCompare.evaluate(injected: injected), name) { error in
                    let compareError = error as? LocationCompareError
                    let expectedError = expected["error"] as? [String: Any]
                    XCTAssertEqual(compareError?.message, expectedError?["message"] as? String, name)
                }
            }
        }
    }

    func testJSONObjectKeysCollapseCanonicallyEquivalentIdentities() throws {
        let json = Data(#"""
        {"A\u030A":"suitable","\u00C5":"unsuitable"}
        """#.utf8)
        let raw = try JSONSerialization.jsonObject(with: json)
        let ns = try XCTUnwrap(raw as? NSDictionary)
        XCTAssertEqual(ns.count, 2, "NSDictionary preserves both JSON object keys")
        let bridged = try XCTUnwrap(raw as? [String: Any])
        XCTAssertEqual(
            bridged.count,
            1,
            "bridging to [String: Any] collapses canonically equivalent keys; object overlays are not portable"
        )
    }

    func testJSONEvalPathAppliesDistinctSuitabilityToCanonicalEquivalents() throws {
        let json = Data(#"""
        {
          "candidates": [
            {
              "key": "A\u030A",
              "public_score": 70,
              "night_conditions_score": 70,
              "avg_cloud_cover": 5,
              "fog_score": 5,
              "avg_wind_speed": 5,
              "distance_miles": 8,
              "latitude": 40,
              "longitude": -74
            },
            {
              "key": "\u00C5",
              "public_score": 70,
              "night_conditions_score": 70,
              "avg_cloud_cover": 5,
              "fog_score": 5,
              "avg_wind_speed": 5,
              "distance_miles": 8,
              "latitude": 40,
              "longitude": -74
            }
          ],
          "suitability": [
            {"key": "A\u030A", "suitability": "unsuitable"},
            {"key": "\u00C5", "suitability": "suitable"}
          ]
        }
        """#.utf8)
        let raw = try JSONSerialization.jsonObject(with: json)
        let injected = try XCTUnwrap(raw as? [String: Any])
        let result = try LocationCompare.evaluate(injected: injected)
        XCTAssertEqual(result["ranking"] as? [String], ["\u{00C5}", "A\u{030A}"])
        let locations = try XCTUnwrap(result["locations"] as? [[String: Any]])
        XCTAssertEqual(locations[0]["key"] as? String, "\u{00C5}")
        XCTAssertEqual(locations[0]["suitability"] as? String, "suitable")
        XCTAssertEqual(locations[1]["key"] as? String, "A\u{030A}")
        XCTAssertEqual(locations[1]["suitability"] as? String, "unsuitable")
    }

    func testObjectShapedSuitabilityOverlayIsRejected() {
        XCTAssertThrowsError(
            try LocationCompare.evaluate(injected: [
                "candidates": [[
                    "key": "here",
                    "public_score": 80,
                    "night_conditions_score": 80,
                    "avg_cloud_cover": 1,
                    "fog_score": 1,
                    "avg_wind_speed": 1,
                    "distance_miles": 1,
                    "latitude": 1,
                    "longitude": 1,
                ]],
                "suitability": ["here": "suitable"],
            ])
        ) { error in
            XCTAssertEqual(
                (error as? LocationCompareError)?.message,
                "suitability must be an array"
            )
        }
    }

    func testUTF8KeyOrderDiffersFromSwiftCanonicalEquivalence() throws {
        let combining = "A\u{030A}"
        let precomposed = "\u{00C5}"
        XCTAssertEqual(combining, precomposed, "Swift String equality is canonical; the contract must not be")
        XCTAssertNotEqual(Array(combining.utf8), Array(precomposed.utf8))
        XCTAssertTrue(LocationCompare.keyIsLess(combining, than: precomposed))
        XCTAssertFalse(LocationCompare.keyIsLess(precomposed, than: combining))
        XCTAssertTrue(LocationCompare.keyIsLess("ss", than: "\u{00DF}"))
        XCTAssertTrue(LocationCompare.keyIsLess("z", than: "\u{00E4}"))
        let ranked = try LocationCompare.compare([
            candidate(key: precomposed),
            candidate(key: "z"),
            candidate(key: combining),
            candidate(key: "\u{00E4}"),
        ])
        XCTAssertEqual(ranked.map(\.key), [combining, "z", precomposed, "\u{00E4}"])
    }

    func testOmittedNightConditionsScoreIsNotInferred() {
        XCTAssertThrowsError(
            try LocationCompare.evaluate(injected: [
                "candidates": [[
                    "key": "here",
                    "public_score": 80,
                    "avg_cloud_cover": 1,
                    "fog_score": 1,
                    "avg_wind_speed": 1,
                    "distance_miles": 1,
                    "latitude": 1,
                    "longitude": 1,
                ]],
            ])
        ) { error in
            XCTAssertEqual(
                (error as? LocationCompareError)?.message,
                "night_conditions_score must be a finite JSON number"
            )
        }
    }

    func testBoolScoresAreRejected() {
        XCTAssertThrowsError(
            try LocationCompare.evaluate(injected: [
                "candidates": [[
                    "key": "here",
                    "public_score": true,
                    "night_conditions_score": 80,
                    "avg_cloud_cover": 1,
                    "fog_score": 1,
                    "avg_wind_speed": 1,
                    "distance_miles": 1,
                    "latitude": 1,
                    "longitude": 1,
                ]],
            ])
        ) { error in
            XCTAssertEqual(
                (error as? LocationCompareError)?.message,
                "public_score must be a finite JSON number"
            )
        }
    }

    private func candidate(
        key: String,
        publicScore: Int = 70,
        cloud: Double = 5,
        fog: Int = 5,
        wind: Double = 5,
        distance: Double = 8,
        latitude: Double = 40,
        longitude: Double = -74,
        suitability: LocationCompareSuitability = .unchecked
    ) -> LocationCompareCandidate {
        LocationCompareCandidate(
            key: key,
            publicScore: publicScore,
            nightConditionsScore: publicScore,
            avgCloudCover: cloud,
            fogScore: fog,
            avgWindSpeed: wind,
            distanceMiles: distance,
            latitude: latitude,
            longitude: longitude,
            suitability: suitability
        )
    }

    private func locationScore(
        score: Int,
        cloud: Double = 10,
        fog: Int = 10,
        wind: Double = 10,
        suitability: LocationSuitabilityStatus = .unchecked,
        distance: Double = 5,
        latitude: Double = 40,
        longitude: Double = -74
    ) throws -> LocationScore {
        LocationScore(
            point: GridPoint(
                coordinate: Coordinate(latitude: latitude, longitude: longitude),
                distanceMiles: distance,
                bearing: 0
            ),
            score: score,
            nightQuality: NightQualityAssessment(
                rating: .good,
                summary: "",
                details: NightQualityAssessment.Details(
                    cloudCoverScore: 0,
                    fogScoreAvg: 0,
                    moonIlluminationAvg: 0,
                    windSpeedAvg: 0
                ),
                bestWindow: nil,
                hourlyRatings: [],
                nightStart: Date(timeIntervalSince1970: 0),
                nightEnd: Date(timeIntervalSince1970: 1)
            ),
            fogScore: FogScore(score: fog, factors: []),
            avgCloudCover: cloud,
            avgWindSpeed: wind,
            suitability: suitability,
            summary: ""
        )
    }

    private func jsonObject(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let raw = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(raw as? [String: Any])
    }
}

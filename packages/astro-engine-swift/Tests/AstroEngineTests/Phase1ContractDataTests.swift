import XCTest
import Foundation
@testable import AstroEngine

/// Additive Phase 1 drift checks: contract JSON vs the Swift runtime data model.
/// Scoring calibration and the curated catalog are decoded by the production reader.
final class Phase1ContractDataTests: XCTestCase {
    func testLightPollutionIdentityJSONMatchesSwiftLiterals() throws {
        let json = try loadJSON("data/identity/light-pollution-dataset.json")
        XCTAssertEqual(json["dataset_id"] as? String, LightPollutionDatasetIdentity.current.datasetID)
        XCTAssertEqual(
            F3ObservingQualityContractSupport.jsonInt(json["dataset_revision"]),
            LightPollutionDatasetIdentity.current.datasetRevision
        )
        XCTAssertEqual(
            F3ObservingQualityContractSupport.jsonInt(json["format_version"]),
            LightPollutionDatasetIdentity.current.formatVersion
        )
        let plausible = try XCTUnwrap(F3ObservingQualityContractSupport.asObject(json["plausible_brightness"]))
        XCTAssertEqual(
            F3ObservingQualityContractSupport.jsonDouble(plausible["min"]),
            ModeledZenithBrightnessValidity.minimumPlausibleBrightness
        )
        XCTAssertEqual(
            F3ObservingQualityContractSupport.jsonDouble(plausible["max"]),
            ModeledZenithBrightnessValidity.maximumPlausibleBrightness
        )
        XCTAssertEqual(
            F3ObservingQualityContractSupport.jsonDouble(json["max_coordinate_distance_meters"]),
            ModeledZenithBrightnessValidity.maxCoordinateDistanceMeters
        )
    }

    func testNightQualityRatingThresholdsMatchRuntimeCalibration() throws {
        let json = try loadJSON("data/calibration/night-quality.json")
        let decoded = try EngineCalibration.loadFromContractsRoot().nightQuality
        let thresholds = try XCTUnwrap(F3ObservingQualityContractSupport.asObject(json["rating_thresholds"]))
        XCTAssertEqual(
            F3ObservingQualityContractSupport.jsonDouble(thresholds["excellent_max"]),
            decoded.ratingThresholds.excellentMax
        )
        XCTAssertEqual(
            F3ObservingQualityContractSupport.jsonDouble(thresholds["good_max"]),
            decoded.ratingThresholds.goodMax
        )
        XCTAssertEqual(
            F3ObservingQualityContractSupport.jsonDouble(thresholds["fair_max"]),
            decoded.ratingThresholds.fairMax
        )
        XCTAssertEqual(
            NightQualityAssessment.Rating.Thresholds.excellentMax,
            decoded.ratingThresholds.excellentMax
        )
        XCTAssertEqual(
            NightQualityAssessment.Rating.Thresholds.goodMax,
            decoded.ratingThresholds.goodMax
        )
        XCTAssertEqual(
            NightQualityAssessment.Rating.Thresholds.fairMax,
            decoded.ratingThresholds.fairMax
        )
        let floor = try XCTUnwrap(F3ObservingQualityContractSupport.asObject(json["cloud_floor"]))
        XCTAssertEqual(
            F3ObservingQualityContractSupport.jsonDouble(floor["fair_max"]),
            decoded.cloudFloor.fairMax
        )
        XCTAssertEqual(
            F3ObservingQualityContractSupport.jsonInt(floor["cloud_cover_min"]),
            decoded.cloudFloor.cloudCoverMin
        )
        XCTAssertEqual(decoded.cloudFloor.fairMax, decoded.ratingThresholds.fairMax)
    }

    func testPublicScoreJSONBasesMatchCalculateScoreEmptyHours() throws {
        let json = try loadJSON("data/calibration/night-quality.json")
        let bases = try XCTUnwrap(F3ObservingQualityContractSupport.asObject(json["public_score"]))
        let decoded = try EngineCalibration.loadFromContractsRoot().nightQuality.publicScore
        XCTAssertEqual(decoded.excellentBase, F3ObservingQualityContractSupport.jsonInt(bases["excellent_base"]))
        XCTAssertEqual(decoded.goodBase, F3ObservingQualityContractSupport.jsonInt(bases["good_base"]))
        XCTAssertEqual(decoded.fairBase, F3ObservingQualityContractSupport.jsonInt(bases["fair_base"]))
        XCTAssertEqual(decoded.poorBase, F3ObservingQualityContractSupport.jsonInt(bases["poor_base"]))
        XCTAssertEqual(
            NightConditionsScoring.publicScore(emptyAssessment(.excellent)),
            F3ObservingQualityContractSupport.jsonInt(bases["excellent_base"])
        )
        XCTAssertEqual(
            NightConditionsScoring.publicScore(emptyAssessment(.good)),
            F3ObservingQualityContractSupport.jsonInt(bases["good_base"])
        )
        XCTAssertEqual(
            NightConditionsScoring.publicScore(emptyAssessment(.fair)),
            F3ObservingQualityContractSupport.jsonInt(bases["fair_base"])
        )
        XCTAssertEqual(
            NightConditionsScoring.publicScore(emptyAssessment(.poor)),
            F3ObservingQualityContractSupport.jsonInt(bases["poor_base"])
        )
    }

    func testEquipmentLimitsJSONMatchSwiftLiterals() throws {
        let json = try loadJSON("data/catalog/equipment-limits.json")
        XCTAssertEqual(
            F3ObservingQualityContractSupport.jsonDouble(json["millimeters_per_inch"]),
            EquipmentValidation.millimetersPerInch
        )
        XCTAssertEqual(
            F3ObservingQualityContractSupport.jsonDouble(json["maximum_binocular_magnification"]),
            EquipmentValidation.maximumBinocularMagnification
        )
        XCTAssertEqual(
            F3ObservingQualityContractSupport.jsonDouble(json["maximum_binocular_aperture_millimeters"]),
            EquipmentValidation.maximumBinocularApertureMillimeters
        )
        XCTAssertEqual(
            F3ObservingQualityContractSupport.jsonDouble(json["maximum_telescope_aperture_millimeters"]),
            EquipmentValidation.maximumTelescopeApertureMillimeters
        )
    }

    func testDeepSkyCatalogJSONMatchesSwiftEntries() throws {
        let json = try loadJSON("data/catalog/deep-sky.json")
        let entries = try XCTUnwrap(F3ObservingQualityContractSupport.asArray(json["entries"]))
        let swift = CuratedDeepSkyCatalogProvider().entries()
        let frozenIDs = [
            "m13", "m31", "m2", "m30", "m52", "m11", "m36", "m38", "m57", "m27",
            "ngc7009", "ngc7293", "m51", "m64", "m77", "m81", "m82", "m92",
            "albireo", "epsilon-lyrae", "m45", "m42", "double-cluster", "m5",
            "m3", "m16", "m20", "m33", "m101",
        ]
        XCTAssertEqual(entries.count, 29)
        XCTAssertEqual(entries.count, swift.count)
        XCTAssertEqual(swift.map(\.id), frozenIDs)
        XCTAssertEqual(Set(frozenIDs).count, frozenIDs.count)

        let byID = Dictionary(uniqueKeysWithValues: swift.map { ($0.id, $0) })
        var jsonIDs: [String] = []
        for raw in entries {
            let obj = try XCTUnwrap(F3ObservingQualityContractSupport.asObject(raw))
            let id = try XCTUnwrap(obj["id"] as? String)
            jsonIDs.append(id)
            let entry = try XCTUnwrap(byID[id], "catalog id \(id) missing from Swift")
            XCTAssertEqual(obj["common_name"] as? String, entry.commonName, id)
            XCTAssertEqual(obj["catalog_name"] as? String, entry.catalogName, id)
            XCTAssertEqual(obj["object_type"] as? String, snakeCase(entry.objectType.rawValue), id)
            XCTAssertEqual(obj["constellation"] as? String, entry.constellation, id)
            XCTAssertEqual(F3ObservingQualityContractSupport.jsonDouble(obj["right_ascension"]), entry.rightAscension, id)
            XCTAssertEqual(F3ObservingQualityContractSupport.jsonDouble(obj["declination"]), entry.declination, id)
            XCTAssertEqual(F3ObservingQualityContractSupport.jsonDouble(obj["magnitude"]), entry.magnitude, id)
            XCTAssertEqual(obj["apparent_size"] as? String, entry.apparentSize, id)
            XCTAssertEqual(F3ObservingQualityContractSupport.jsonDouble(obj["difficulty"]), entry.difficulty, id)
            XCTAssertEqual(obj["recommended_equipment"] as? String, snakeCase(entry.recommendedEquipment.rawValue), id)
            XCTAssertEqual(obj["observing_intent"] as? String, entry.observingIntent.rawValue, id)
            XCTAssertEqual(obj["notes"] as? String, entry.notes, id)
            if let override = entry.displayTypeNameOverride {
                XCTAssertEqual(obj["display_type_name_override"] as? String, override, id)
            } else {
                XCTAssertNil(obj["display_type_name_override"], id)
            }
            if let sb = entry.surfaceBrightness {
                XCTAssertEqual(F3ObservingQualityContractSupport.jsonDouble(obj["surface_brightness"]), sb, id)
            } else {
                XCTAssertTrue(F3ObservingQualityContractSupport.isNull(obj["surface_brightness"]), id)
            }
        }
        XCTAssertEqual(jsonIDs, frozenIDs)

        let m20 = try XCTUnwrap(byID["m20"])
        XCTAssertEqual(m20.rightAscension, 18.0433, accuracy: 0.0001)
        XCTAssertEqual(m20.declination, -23.0297, accuracy: 0.0001)
        XCTAssertEqual(m20.magnitude, 6.3)
        let m64 = try XCTUnwrap(byID["m64"])
        XCTAssertEqual(m64.magnitude, 8.5)
        XCTAssertEqual(byID["double-cluster"]?.displayTypeNameOverride, "Open Cluster Pair")
    }

    func testEngineVersionIs100() throws {
        XCTAssertEqual(try F3ObservingQualityContractSupport.engineSemver(), "1.0.0")
    }

    private func loadJSON(_ relative: String) throws -> [String: Any] {
        let url = try F3ObservingQualityContractSupport.contractsDirectory()
            .appendingPathComponent(relative)
        return try F3ObservingQualityContractSupport.loadJSONObject(url)
    }

    private func emptyAssessment(_ rating: NightQualityAssessment.Rating) -> NightQualityAssessment {
        NightQualityAssessment(
            rating: rating,
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
            nightEnd: Date(timeIntervalSince1970: 0)
        )
    }

    private func snakeCase(_ raw: String) -> String {
        raw.reduce(into: "") { result, ch in
            if ch.isUppercase {
                if !result.isEmpty { result.append("_") }
                result.append(contentsOf: String(ch).lowercased())
            } else {
                result.append(ch)
            }
        }
    }
}

import XCTest
import Foundation
@testable import AstroEngine

final class DeepSkyCatalogTests: XCTestCase {
    private let frozenIDs = [
        "m13", "m31", "m2", "m30", "m52", "m11", "m36", "m38", "m57", "m27",
        "ngc7009", "ngc7293", "m51", "m64", "m77", "m81", "m82", "m92",
        "albireo", "epsilon-lyrae", "m45", "m42", "double-cluster", "m5",
        "m3", "m16", "m20", "m33", "m101",
    ]

    func testLoadFromContractsRootMatchesFrozenInventory() throws {
        let entries = try DeepSkyCatalog.loadFromContractsRoot()
        XCTAssertEqual(entries.map(\.id), frozenIDs)
        XCTAssertEqual(entries.count, 29)
        XCTAssertEqual(Set(entries.map(\.id)).count, 29)
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        let m20 = try XCTUnwrap(byID["m20"])
        XCTAssertEqual(m20.rightAscension, 18.0433, accuracy: 0.0001)
        XCTAssertEqual(m20.declination, -23.0297, accuracy: 0.0001)
        XCTAssertEqual(m20.magnitude, 6.3)
        XCTAssertEqual(try XCTUnwrap(byID["m64"]).magnitude, 8.5)
        XCTAssertEqual(byID["double-cluster"]?.displayTypeNameOverride, "Open Cluster Pair")
        XCTAssertNil(byID["m13"]?.displayTypeNameOverride)
        XCTAssertNil(byID["m36"]?.surfaceBrightness)
        XCTAssertEqual(byID["m13"]?.objectType, .globularCluster)
        XCTAssertEqual(byID["m13"]?.recommendedEquipment, .binoculars)
        XCTAssertEqual(CuratedDeepSkyCatalogProvider().entries().map(\.id), frozenIDs)
    }

    func testContractDTOOmitsOverrideWhenNilAndKeepsNullSurfaceBrightness() throws {
        let entries = try DeepSkyCatalog.loadFromContractsRoot()
        let result = DeepSkyCatalog.contractResult(from: entries)
        let encoded = try XCTUnwrap(result["entries"] as? [[String: Any]])
        let m13 = try XCTUnwrap(encoded.first { $0["id"] as? String == "m13" })
        XCTAssertNil(m13["display_type_name_override"])
        XCTAssertTrue(m13["surface_brightness"] is NSNumber)
        let m36 = try XCTUnwrap(encoded.first { $0["id"] as? String == "m36" })
        XCTAssertTrue(F3ObservingQualityContractSupport.isNull(m36["surface_brightness"]))
        let pair = try XCTUnwrap(encoded.first { $0["id"] as? String == "double-cluster" })
        XCTAssertEqual(pair["display_type_name_override"] as? String, "Open Cluster Pair")
        XCTAssertEqual(pair["object_type"] as? String, "open_cluster")
    }

    func testBoolIsRejectedAsNumber() throws {
        XCTAssertThrowsError(try DeepSkyCatalog.decodeDocument([
            "entries": [[
                "id": "m13",
                "common_name": "M13",
                "catalog_name": "M13",
                "object_type": "globular_cluster",
                "constellation": "Hercules",
                "right_ascension": true,
                "declination": 36.4613,
                "magnitude": 5.8,
                "apparent_size": "20 arcmin",
                "surface_brightness": 12.0,
                "difficulty": 0.55,
                "recommended_equipment": "binoculars",
                "observing_intent": "easy",
                "notes": "x",
            ]]
        ])) { error in
            guard let typed = error as? DeepSkyCatalogError, case .invalid(let detail) = typed else {
                return XCTFail("expected invalid, got \(error)")
            }
            XCTAssertTrue(detail.contains("finite JSON number"), detail)
        }
    }

    func testNumericStringIsRejected() throws {
        XCTAssertThrowsError(try DeepSkyCatalog.decodeDocument([
            "entries": [[
                "id": "m13",
                "common_name": "M13",
                "catalog_name": "M13",
                "object_type": "globular_cluster",
                "constellation": "Hercules",
                "right_ascension": "16.6949",
                "declination": 36.4613,
                "magnitude": 5.8,
                "apparent_size": "20 arcmin",
                "surface_brightness": 12.0,
                "difficulty": 0.55,
                "recommended_equipment": "binoculars",
                "observing_intent": "easy",
                "notes": "x",
            ]]
        ]))
    }
}

import Foundation
import SharedCode
import XCTest

final class CuratedDeepSkyCatalogTests: XCTestCase {
    func testCatalogContainsExpectedTargets() {
        let ids = Set(CuratedDeepSkyCatalogProvider().entries().map(\.id))
        XCTAssertTrue([
            "m13", "m31", "m2", "m30", "m52", "m11", "m57", "m27",
            "ngc7009", "ngc7293", "m51", "m64", "m81", "m82", "m92",
            "albireo", "epsilon-lyrae", "m45", "m42", "double-cluster", "m5",
            "m3", "m16", "m20", "m33", "m101"
        ].allSatisfy(ids.contains))
        XCTAssertEqual(ids.count, CuratedDeepSkyCatalogProvider().entries().count)
    }

    func testCatalogAwareNamesAndDisplayTypes() {
        let entries = entriesByID
        XCTAssertEqual(entries["double-cluster"]?.commonName, "NGC 869/884 Double Cluster")
        XCTAssertEqual(entries["double-cluster"]?.objectType, .openCluster)
        XCTAssertEqual(entries["double-cluster"]?.displayTypeNameOverride, "Open Cluster Pair")
        XCTAssertEqual(catalogTarget(id: "double-cluster").displayTypeName, "Open Cluster Pair")
        XCTAssertFalse(catalogTarget(id: "double-cluster").displayTypeName.contains("NGC"))
        XCTAssertEqual(entries["m16"]?.commonName, "M16 Eagle Nebula")
        XCTAssertEqual(entries["m42"]?.commonName, "M42 Orion Nebula")
        XCTAssertEqual(entries["m45"]?.commonName, "M45 Pleiades")
        XCTAssertEqual(entries["m33"]?.commonName, "M33 Triangulum Galaxy")
        XCTAssertEqual(entries["m101"]?.commonName, "M101 Pinwheel Galaxy")

        let expectedLabels = [
            "epsilon-lyrae": "Double Star", "albireo": "Double Star",
            "m57": "Planetary Nebula", "m92": "Globular Cluster", "m31": "Galaxy"
        ]
        for (id, expectedLabel) in expectedLabels {
            XCTAssertEqual(catalogTarget(id: id).displayTypeName, expectedLabel, id)
        }
    }

    func testDisplayTypeOverrideIsModelDrivenRatherThanTargetIDSpecific() {
        let overridden = ObservableTarget(
            id: "any-open-cluster", name: "Any Cluster", type: .deepSky,
            preferredEquipment: .binoculars, difficulty: 0.2,
            displayTypeNameOverride: "Open Cluster Pair", deepSkyObjectType: .openCluster
        )
        let ordinary = ObservableTarget(
            id: "double-cluster", name: "Same ID Without Override", type: .deepSky,
            preferredEquipment: .binoculars, difficulty: 0.2, deepSkyObjectType: .openCluster
        )
        XCTAssertEqual(overridden.displayTypeName, "Open Cluster Pair")
        XCTAssertEqual(ordinary.displayTypeName, "Open Cluster")
    }

    func testObservingIntentAssignments() {
        let targets = targetsByID
        let easy = ["moon", "venus", "jupiter", "saturn", "m13", "m31", "m11", "albireo", "m45", "m42", "double-cluster"]
        let standard = ["mars", "m2", "m30", "m52", "m57", "m27", "ngc7009", "m81", "m82", "m92", "epsilon-lyrae", "m5", "m3", "m16", "m20"]
        let challenge = ["ngc7293", "m51", "m64", "m33", "m101"]
        for id in easy { XCTAssertEqual(targets[id]?.observingIntent, .easy, id) }
        for id in standard { XCTAssertEqual(targets[id]?.observingIntent, .standard, id) }
        for id in challenge { XCTAssertEqual(targets[id]?.observingIntent, .challenge, id) }
        XCTAssertEqual(targets.count, easy.count + standard.count + challenge.count)
    }

    func testUnsupportedOuterPlanetsAreAbsent() {
        let ids = Set(targetsByID.keys)
        XCTAssertFalse(ids.contains("uranus"))
        XCTAssertFalse(ids.contains("neptune"))
    }

    func testDescriptionsSetRealisticVisualExpectations() throws {
        let m16 = try XCTUnwrap(entriesByID["m16"])
        let m20 = try XCTUnwrap(entriesByID["m20"])
        let m33 = try XCTUnwrap(entriesByID["m33"])
        let m101 = try XCTUnwrap(entriesByID["m101"])
        let m31 = try XCTUnwrap(entriesByID["m31"])
        XCTAssertTrue(m16.notes.contains("mainly an imaging target"))
        XCTAssertFalse(m16.notes.localizedCaseInsensitiveContains("visible Pillars"))
        XCTAssertTrue(m20.notes.contains("do not expect photographic color"))
        XCTAssertTrue(m33.notes.contains("low surface brightness"))
        XCTAssertTrue(m101.notes.contains("dark-sky challenge"))
        XCTAssertTrue(m31.notes.contains("suburban views may show mostly its bright core"))
    }

    private var entriesByID: [String: DeepSkyCatalogEntry] {
        Dictionary(uniqueKeysWithValues: CuratedDeepSkyCatalogProvider().entries().map { ($0.id, $0) })
    }

    private var targetsByID: [String: ObservableTarget] {
        Dictionary(uniqueKeysWithValues: DefaultTargetCatalogProvider().targets(for: context).map { ($0.id, $0) })
    }

    private func catalogTarget(id: String) -> ObservableTarget {
        try! XCTUnwrap(targetsByID[id])
    }

    private var context: TargetRecommendationContext {
        let start = Date(timeIntervalSince1970: 1_772_409_600)
        let end = start.addingTimeInterval(32_400)
        return TargetRecommendationContext(
            location: CachedLocation(name: "Test", latitude: 34, longitude: -118, elevation: 0),
            astronomicalNightStart: start,
            astronomicalNightEnd: end,
            nightQuality: NightQualityAssessment(
                rating: .good,
                summary: "Test",
                details: .init(cloudCoverScore: 5, fogScoreAvg: 5, moonIlluminationAvg: 0, windSpeedAvg: 2),
                bestWindow: .init(start: start, end: end),
                hourlyRatings: [],
                nightStart: start,
                nightEnd: end
            ),
            moonInfo: MoonInfo(phase: 0, phaseName: "New Moon", altitude: -5, illumination: 0, emoji: "")
        )
    }
}

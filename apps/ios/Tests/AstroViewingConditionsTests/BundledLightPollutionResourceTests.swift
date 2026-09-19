@testable import SharedCode
import XCTest

final class BundledLightPollutionResourceTests: XCTestCase {

    override func tearDown() async throws {
        await LightPollutionProviderBootstrap.shared.resetForTesting()
        try await super.tearDown()
    }

    func testBundledResourceIsLocatableAndExpectedSize() throws {
        let url = try XCTUnwrap(
            BundledLightPollutionResource.resourceURL(in: [Bundle.main]),
            "Production LPATLAS1 resource must be packaged in the host app. "
                + "Expected \(BundledLightPollutionResource.resourceName)."
                + BundledLightPollutionResource.resourceExtension
        )
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        XCTAssertEqual(size, BundledLightPollutionResource.expectedByteCount)
    }

    func testBundledProviderLoadsAndMatchesHomeAndStubStewart() throws {
        let provider = try BundledLightPollutionResource.loadProvider(
            preferredBundles: [Bundle.main],
            verifyChecksum: true
        )

        let home = try XCTUnwrap(
            provider.modeledZenithSkyBrightness(latitude: 45.45, longitude: -122.75)
        )
        let stub = try XCTUnwrap(
            provider.modeledZenithSkyBrightness(latitude: 45.736, longitude: -123.192)
        )
        XCTAssertEqual(home, 18.539606394730214, accuracy: 1e-6)
        XCTAssertEqual(stub, 21.341771681477702, accuracy: 1e-6)

        // Out of coverage → nil (not pristine)
        XCTAssertNil(provider.modeledZenithSkyBrightness(latitude: 80.0, longitude: 0.0))
    }

    func testBootstrapLoadsOnceAndServesAssessments() async throws {
        await LightPollutionProviderBootstrap.shared.resetForTesting()
        let t0 = CFAbsoluteTimeGetCurrent()
        let provider = await LightPollutionProviderBootstrap.shared.ensureLoaded(
            preferredBundles: [Bundle.main]
        )
        let initSec = CFAbsoluteTimeGetCurrent() - t0
        let loaded = try XCTUnwrap(provider, "Bootstrap must load bundled LPATLAS1")

        let tFirst = CFAbsoluteTimeGetCurrent()
        let first = loaded.modeledZenithSkyBrightness(latitude: 45.45, longitude: -122.75)
        let firstSec = CFAbsoluteTimeGetCurrent() - tFirst

        let tWarm = CFAbsoluteTimeGetCurrent()
        for _ in 0..<500 {
            _ = loaded.modeledZenithSkyBrightness(latitude: 45.45, longitude: -122.75)
        }
        let warmSec = (CFAbsoluteTimeGetCurrent() - tWarm) / 500.0

        print(
            String(
                format: "LPATLAS1 bootstrap init=%.3fs first_us=%.1f warm_us=%.1f",
                initSec,
                firstSec * 1e6,
                warmSec * 1e6
            )
        )

        XCTAssertEqual(first!, 18.539606394730214, accuracy: 1e-6)
        let state = await LightPollutionProviderBootstrap.shared.currentState()
        XCTAssertEqual(state, .ready)

        // Second ensureLoaded must be cheap and return same instance path
        let t2 = CFAbsoluteTimeGetCurrent()
        let again = await LightPollutionProviderBootstrap.shared.ensureLoaded(
            preferredBundles: [Bundle.main]
        )
        let secondSec = CFAbsoluteTimeGetCurrent() - t2
        XCTAssertNotNil(again)
        XCTAssertLessThan(secondSec, 0.05, "cached load should not re-validate full tree")

        let service = ObservingQualityService(lightPollutionProvider: loaded)
        let homeScore = service.assess(
            nightConditionsScore: 93,
            latitude: 45.45,
            longitude: -122.75
        )
        // ~18.54 → base ~7, full weight → ~86
        XCTAssertEqual(homeScore.score, 86)
        XCTAssertNotNil(homeScore.lightPollution)

        let stubScore = service.assess(
            nightConditionsScore: 93,
            latitude: 45.736,
            longitude: -123.192
        )
        // ~21.34 → base ~1 → 92
        XCTAssertEqual(stubScore.score, 92)
    }

    func testResourceConstantsMatchDocumentedArtifact() {
        XCTAssertEqual(BundledLightPollutionResource.resourceName, "light_pollution_global_v1")
        XCTAssertEqual(BundledLightPollutionResource.resourceExtension, "bin")
        XCTAssertEqual(BundledLightPollutionResource.expectedByteCount, 10_328_230)
        XCTAssertEqual(
            BundledLightPollutionResource.expectedSHA256,
            "b9c60e83d866f28e781dcc89a4ad302597012cdb9df6c94743efdd44be86dce4"
        )
    }
}

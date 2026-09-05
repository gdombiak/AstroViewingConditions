import XCTest
import Foundation
@testable import AstroEngine

final class FixtureRootTests: XCTestCase {
    func testNamedProviderFixturesExist() throws {
        let relativePaths = [
            "providers/open-meteo/forecast/happy-path.json",
            "providers/open-meteo/forecast/missing-fields.json",
            "providers/open-meteo/forecast/negative-values.json",
            "providers/open-meteo/forecast/tz-from-offset-only.json",
            "providers/open-meteo/forecast/layered-seeing-transparency.json",
            "providers/open-meteo/forecast/short-optional-arrays.json",
            "providers/open-meteo/forecast/malformed-time-skipped.json",
            "providers/n2yo/visualpasses/two-passes.json",
            "providers/n2yo/visualpasses/empty-passes-array.json",
            "providers/n2yo/visualpasses/nil-passes.json",
            "providers/lpatlas1/lpatlas1_tiny_constant.bin",
            "providers/lpatlas1/lpatlas1_tiny_constant.lookups.json",
        ]
        for relativePath in relativePaths {
            let url = try FixtureRoot.url(relativePath)
            XCTAssertTrue(
                FileManager.default.isReadableFile(atPath: url.path),
                relativePath
            )
        }
    }

    func testDirectoryHonorsContractsRootOverride() throws {
        let walked = try FixtureRoot.directory(
            environment: [:],
            startingAt: URL(fileURLWithPath: #filePath)
        )
        let viaEnv = try FixtureRoot.directory(
            environment: [
                "CONTRACTS_ROOT": walked.deletingLastPathComponent().path
            ]
        )
        XCTAssertEqual(
            viaEnv.resolvingSymlinksInPath().standardizedFileURL.path,
            walked.resolvingSymlinksInPath().standardizedFileURL.path
        )
    }

    func testMissingFixtureFailsClosed() {
        XCTAssertThrowsError(
            try FixtureRoot.url("providers/open-meteo/forecast/does-not-exist.json")
        ) { error in
            XCTAssertEqual(
                error as? FixtureRootError,
                .fixtureMissing("providers/open-meteo/forecast/does-not-exist.json")
            )
        }
    }

    func testParentTraversalIsRejected() {
        XCTAssertThrowsError(
            try FixtureRoot.url("../data/calibration/observing-quality.json")
        ) { error in
            XCTAssertEqual(
                error as? FixtureRootError,
                .refEscape("../data/calibration/observing-quality.json")
            )
        }
    }
}

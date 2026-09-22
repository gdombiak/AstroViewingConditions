import XCTest
@testable import AstroEngine

final class OpticsTests: XCTestCase {
    func testVirtuosoDelosReportsAllThreeFacts() throws {
        let result = try VisualOptics.evaluate([
            "telescope_focal_length_mm": 750,
            "eyepiece_focal_length_mm": 8,
            "telescope_aperture_mm": 150,
            "afov_degrees": 72,
        ])
        XCTAssertEqual(try number(result, "magnification"), 93.75, accuracy: 1e-9)
        XCTAssertEqual(try number(result, "exit_pupil_mm"), 1.6, accuracy: 1e-9)
        XCTAssertEqual(
            try number(result, "approximate_true_field_of_view_degrees"),
            0.768,
            accuracy: 1e-9
        )
    }

    func testMissingApertureOmitsOnlyExitPupil() throws {
        let result = try VisualOptics.evaluate([
            "telescope_focal_length_mm": 750,
            "eyepiece_focal_length_mm": 24,
            "afov_degrees": 68,
        ])
        XCTAssertEqual(try number(result, "magnification"), 31.25, accuracy: 1e-9)
        XCTAssertTrue(result["exit_pupil_mm"] is NSNull)
        XCTAssertEqual(
            try number(result, "approximate_true_field_of_view_degrees"),
            2.176,
            accuracy: 1e-9
        )
    }

    func testMissingFocalLengthMakesDependentFactsUnavailable() throws {
        let result = try VisualOptics.evaluate([
            "eyepiece_focal_length_mm": 8,
            "telescope_aperture_mm": 150,
            "afov_degrees": 72,
        ])
        XCTAssertTrue(result["magnification"] is NSNull)
        XCTAssertTrue(result["exit_pupil_mm"] is NSNull)
        XCTAssertTrue(result["approximate_true_field_of_view_degrees"] is NSNull)
    }

    func testInvalidInputsAreRejected() {
        XCTAssertThrowsError(try VisualOptics.evaluate([
            "telescope_focal_length_mm": 0,
            "eyepiece_focal_length_mm": 8,
        ]))
        XCTAssertThrowsError(try VisualOptics.evaluate([
            "telescope_focal_length_mm": true,
            "eyepiece_focal_length_mm": 8,
        ]))
        XCTAssertThrowsError(try VisualOptics.evaluate([
            "telescope_focal_length_mm": 750,
            "eyepiece_focal_length_mm": 8,
            "afov_degrees": 181,
        ]))
        XCTAssertThrowsError(try VisualOptics.evaluate([
            "telescope_focal_length_mm": 750,
            "eyepiece_focal_length_mm": 8,
            "name": "Delos",
        ]))
    }

    func testApparentFieldOf180IsAccepted() throws {
        let result = try VisualOptics.evaluate([
            "telescope_focal_length_mm": 1000,
            "eyepiece_focal_length_mm": 10,
            "afov_degrees": 180,
        ])
        XCTAssertEqual(
            try number(result, "approximate_true_field_of_view_degrees"),
            1.8,
            accuracy: 1e-9
        )
    }

    private func number(_ result: [String: Any], _ key: String) throws -> Double {
        try XCTUnwrap(result[key] as? Double)
    }
}

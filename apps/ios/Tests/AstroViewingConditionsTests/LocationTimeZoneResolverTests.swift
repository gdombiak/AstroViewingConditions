import CoreLocation
import SharedCode
import XCTest

final class LocationTimeZoneResolverTests: XCTestCase {
    func testSuccessfulGeocoderTimeZoneIsUsed() async throws {
        let expected = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let result = await LocationTimeZoneResolver.resolve(
            latitude: 34.05, longitude: -118.24, timeout: 0.1,
            geocoder: { _ in expected }
        )
        XCTAssertEqual(result.identifier, expected.identifier)
    }

    func testGeocoderFailureFallsBackToLongitudeApproximation() async {
        let longitude = 30.0
        let result = await LocationTimeZoneResolver.resolve(
            latitude: 0, longitude: longitude, timeout: 0.1,
            geocoder: { _ in throw TestError.geocoderFailure }
        )
        XCTAssertEqual(result, LocationTimeZoneResolver.approximate(longitude: longitude))
    }

    func testGeocoderTimeoutFallsBackQuickly() async {
        let longitude = -75.0
        let start = Date()
        let result = await LocationTimeZoneResolver.resolve(
            latitude: 40, longitude: longitude, timeout: 0.01,
            geocoder: { _ in
                await withUnsafeContinuation { (_: UnsafeContinuation<Void, Never>) in }
                return nil
            }
        )
        XCTAssertEqual(result, LocationTimeZoneResolver.approximate(longitude: longitude))
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
    }

    private enum TestError: Error { case geocoderFailure }
}

import XCTest
@testable import AstroEngine

final class LocationDistanceTests: XCTestCase {
    func testGreatCircleCases() throws {
        let origin = Coordinate(latitude: 0, longitude: 0)
        XCTAssertEqual(LocationDistance.miles(from: origin, to: origin), 0)
        XCTAssertEqual(
            LocationDistance.miles(from: origin, to: Coordinate(latitude: 0, longitude: 1)),
            69.09332413987235, accuracy: 1e-9
        )
        XCTAssertEqual(
            LocationDistance.miles(
                from: Coordinate(latitude: 0, longitude: 179),
                to: Coordinate(latitude: 0, longitude: -179)
            ),
            138.18664827974413, accuracy: 1e-9
        )
    }

    func testStrictTransport() {
        XCTAssertThrowsError(try LocationDistance.evaluate([
            "from": ["latitude": true, "longitude": 0],
            "to": ["latitude": 0, "longitude": 0],
        ]))
        XCTAssertThrowsError(try LocationDistance.evaluate([
            "from": ["latitude": 91, "longitude": 0],
            "to": ["latitude": 0, "longitude": 0],
        ]))
    }
}

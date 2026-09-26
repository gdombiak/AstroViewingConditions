import Foundation
import MapKit
import SharedCode
import SwiftData
import XCTest
@testable import AstroViewingConditions

final class LocationSearchServicesTests: XCTestCase {
    func testOnlyPlacemarkNotFoundIsAnEmptySearch() async {
        let notFound = NSError(
            domain: MKErrorDomain,
            code: Int(MKError.Code.placemarkNotFound.rawValue)
        )
        let serverFailure = NSError(
            domain: MKErrorDomain,
            code: Int(MKError.Code.serverFailure.rawValue)
        )
        let unrelatedError = NSError(domain: "OtherService", code: notFound.code)

        let mapsNoMatch = await PlaceSearchService.isNoMatch(notFound)
        let mapsFailure = await PlaceSearchService.isNoMatch(serverFailure)
        let otherFailure = await PlaceSearchService.isNoMatch(unrelatedError)
        XCTAssertTrue(mapsNoMatch)
        XCTAssertFalse(mapsFailure)
        XCTAssertFalse(otherFailure)
    }

    func testPlaceSubtitleRemovesRepeatedPrimaryName() {
        XCTAssertEqual(
            PlaceSearchResult.subtitle(
                name: "Stub Stewart State Park",
                title: "Stub Stewart State Park, Buxton, OR",
                locality: "Buxton",
                administrativeArea: "OR",
                country: "United States"
            ),
            "Buxton, OR"
        )
    }

    func testPlaceSubtitleFallsBackToLocality() {
        XCTAssertEqual(
            PlaceSearchResult.subtitle(
                name: "Mount Hood",
                title: "Mount Hood",
                locality: nil,
                administrativeArea: "Oregon",
                country: "United States"
            ),
            "Oregon, United States"
        )
    }

    func testElevationRequestAndResponse() async throws {
        let service = TerrainElevationService { request in
            let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
            XCTAssertEqual(components.host, "api.open-meteo.com")
            XCTAssertEqual(components.path, "/v1/elevation")
            XCTAssertEqual(components.queryItems?.first(where: { $0.name == "latitude" })?.value, "45.0")
            XCTAssertEqual(components.queryItems?.first(where: { $0.name == "longitude" })?.value, "-123.0")
            return (
                Data(#"{"elevation":[312.0]}"#.utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }
        let elevation = try await service.elevation(latitude: 45, longitude: -123)
        XCTAssertEqual(elevation, 312)
        let bestEffortElevation = await service.elevationIfAvailable(latitude: 45, longitude: -123)
        XCTAssertEqual(bestEffortElevation, 312)
    }

    func testElevationRejectsMissingValue() async {
        let service = TerrainElevationService { request in
            (
                Data(#"{"elevation":[null]}"#.utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }
        do {
            _ = try await service.elevation(latitude: 45, longitude: -123)
            XCTFail("Expected the missing terrain elevation to be rejected")
        } catch {
            XCTAssertTrue(error is TerrainElevationService.LookupError)
        }
        let bestEffortElevation = await service.elevationIfAvailable(latitude: 45, longitude: -123)
        XCTAssertNil(bestEffortElevation)
    }

    func testElevationTimeoutFallsBackWithoutWaitingForNetwork() async {
        let service = TerrainElevationService(timeout: 0.02) { _ in
            try await Task.sleep(for: .seconds(2))
            throw CancellationError()
        }
        let start = Date()
        let elevation = await service.elevationIfAvailable(latitude: 45, longitude: -123)
        XCTAssertNil(elevation)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }

    @MainActor
    func testSelectedPlacePersistsElevationOrNilFallback() async throws {
        let container = try ModelContainer(
            for: SavedLocation.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let place = PlaceSearchResult(
            name: "Stub Stewart State Park",
            subtitle: "Buxton, OR",
            latitude: 45.0,
            longitude: -123.0
        )
        let successfulLookup = TerrainElevationService { request in
            (
                Data(#"{"elevation":[312.0]}"#.utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }
        let failedLookup = TerrainElevationService(timeout: 0.02) { _ in
            try await Task.sleep(for: .seconds(2))
            throw CancellationError()
        }

        let withElevation = place.savedLocation(elevation: await successfulLookup.elevationIfAvailable(
            latitude: place.latitude,
            longitude: place.longitude
        ))
        let withoutElevation = place.savedLocation(elevation: await failedLookup.elevationIfAvailable(
            latitude: place.latitude,
            longitude: place.longitude
        ))
        context.insert(withElevation)
        context.insert(withoutElevation)
        try context.save()

        let saved = try context.fetch(FetchDescriptor<SavedLocation>())
        XCTAssertEqual(saved.count, 2)
        XCTAssertEqual(saved.first(where: { $0.id == withElevation.id })?.elevation, 312)
        XCTAssertNil(saved.first(where: { $0.id == withoutElevation.id })?.elevation)
    }
}

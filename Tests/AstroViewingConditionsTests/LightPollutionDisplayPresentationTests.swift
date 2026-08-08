@testable import SharedCode
@testable import AstroViewingConditions
import XCTest

// MARK: - Deterministic provider / loader gates

private struct FixedBrightnessProvider: LightPollutionProviding, Sendable {
    let value: Double?
    func modeledZenithSkyBrightness(latitude: Double, longitude: Double) -> Double? { value }
}

/// Suspends each load until released with a specific provider (overlapping-refresh tests).
private actor GatedProviderLoader {
    private struct Pending {
        let continuation: CheckedContinuation<(any LightPollutionProviding)?, Never>
    }

    private var entryWaiter: CheckedContinuation<Void, Never>?
    private var enteredCount = 0
    private var pending: [Pending] = []

    var loadEntryCount: Int { enteredCount }

    func load() async -> (any LightPollutionProviding)? {
        enteredCount += 1
        if let entryWaiter {
            self.entryWaiter = nil
            entryWaiter.resume()
        }
        return await withCheckedContinuation { continuation in
            pending.append(Pending(continuation: continuation))
        }
    }

    func waitUntilEntered(count: Int) async {
        while enteredCount < count {
            await withCheckedContinuation { continuation in
                if enteredCount >= count {
                    continuation.resume()
                } else {
                    entryWaiter = continuation
                }
            }
        }
    }

    /// Completes the oldest pending load (first entered).
    func releaseOldest(with provider: (any LightPollutionProviding)?) {
        guard !pending.isEmpty else { return }
        let item = pending.removeFirst()
        item.continuation.resume(returning: provider)
    }

    /// Completes the newest pending load (last entered) — used to finish B before A.
    func releaseNewest(with provider: (any LightPollutionProviding)?) {
        guard !pending.isEmpty else { return }
        let item = pending.removeLast()
        item.continuation.resume(returning: provider)
    }
}

// MARK: - Presentation tests

final class LightPollutionDisplayPresentationTests: XCTestCase {

    func testCategoryBoundaries() {
        let cases: [(Double, LightPollutionIntensityCategory)] = [
            (13.0, .veryHigh),
            (17.49, .veryHigh),
            (17.5, .high),
            (18.539606, .high),
            (19.49, .high),
            (19.5, .moderate),
            (20.49, .moderate),
            (20.5, .low),
            (21.29, .low),
            (21.3, .veryLow),
            (21.75, .veryLow),
            (22.5, .veryLow),
        ]
        for (brightness, expected) in cases {
            XCTAssertEqual(
                LightPollutionIntensityCategory.category(forValidatedBrightness: brightness),
                expected,
                "brightness \(brightness)"
            )
        }
    }

    func testOneDecimalFormattingAndDisplayValue() throws {
        let home = try XCTUnwrap(LightPollutionDisplayPresentation.available(brightness: 18.539606394730214))
        XCTAssertEqual(home.category, .high)
        XCTAssertEqual(home.formattedBrightness, "18.5")
        XCTAssertEqual(home.displayValue, "High · 18.5 mag/arcsec²")

        let pristine = try XCTUnwrap(LightPollutionDisplayPresentation.available(brightness: 21.75))
        XCTAssertEqual(pristine.formattedBrightness, "21.8")
        XCTAssertEqual(pristine.displayValue, "Very low · 21.8 mag/arcsec²")

        let minBound = try XCTUnwrap(LightPollutionDisplayPresentation.available(brightness: 13.0))
        XCTAssertEqual(minBound.displayValue, "Very high · 13.0 mag/arcsec²")

        let maxBound = try XCTUnwrap(LightPollutionDisplayPresentation.available(brightness: 22.5))
        XCTAssertEqual(maxBound.displayValue, "Very low · 22.5 mag/arcsec²")
    }

    func testUnavailableForInvalidValues() {
        XCTAssertEqual(LightPollutionDisplayPresentation.resolve(rawBrightness: nil), .unavailable)
        XCTAssertEqual(LightPollutionDisplayPresentation.resolve(rawBrightness: .nan), .unavailable)
        XCTAssertEqual(LightPollutionDisplayPresentation.resolve(rawBrightness: .infinity), .unavailable)
        XCTAssertEqual(LightPollutionDisplayPresentation.resolve(rawBrightness: -.infinity), .unavailable)
        XCTAssertEqual(LightPollutionDisplayPresentation.resolve(rawBrightness: 12.99), .unavailable)
        XCTAssertEqual(LightPollutionDisplayPresentation.resolve(rawBrightness: 22.51), .unavailable)
        XCTAssertNil(LightPollutionDisplayPresentation.available(brightness: .nan))
        XCTAssertNil(LightPollutionDisplayPresentation.available(brightness: 12.0))
    }

    func testAccessibilityWording() throws {
        let home = try XCTUnwrap(LightPollutionDisplayPresentation.available(brightness: 18.54))
        XCTAssertEqual(
            home.accessibilityLabel,
            "Light pollution, High, modeled sky brightness 18.5 magnitudes per square arcsecond"
        )
        XCTAssertFalse(home.accessibilityLabel.contains("·"))
        XCTAssertFalse(home.accessibilityLabel.contains("mag/arcsec"))
        XCTAssertEqual(
            LightPollutionDisplayPresentation.unavailableAccessibilityLabel,
            "Light pollution unavailable"
        )
    }

    func testListFooterAndMetricLabels() {
        XCTAssertEqual(
            LightPollutionDisplayPresentation.listFooterExplanation,
            "Higher mag/arcsec² values indicate darker skies. Modeled estimates may differ from local conditions."
        )
        XCTAssertEqual(LightPollutionDisplayPresentation.metricLabel, "Light pollution")
        XCTAssertEqual(LightPollutionDisplayPresentation.coordinatesLabel, "Coordinates")
    }

    // MARK: - Model resolution (identity + coordinates)

    func testModelResolveUsesCoordinatesPerLocation() {
        struct MapProvider: LightPollutionProviding {
            let map: [String: Double?]
            func modeledZenithSkyBrightness(latitude: Double, longitude: Double) -> Double? {
                map["\(latitude),\(longitude)"] ?? nil
            }
        }
        let provider = MapProvider(map: [
            "45.45,-122.75": 18.54,
            "45.736,-123.192": 21.34,
            "80.0,0.0": nil,
        ])
        let home = SavedLocationLightPollutionModel.LocationKey(
            id: UUID(), latitude: 45.45, longitude: -122.75
        )
        let stub = SavedLocationLightPollutionModel.LocationKey(
            id: UUID(), latitude: 45.736, longitude: -123.192
        )
        let out = SavedLocationLightPollutionModel.LocationKey(
            id: UUID(), latitude: 80.0, longitude: 0.0
        )
        let invalid = SavedLocationLightPollutionModel.LocationKey(
            id: UUID(), latitude: 91, longitude: 0
        )

        if case .available(let p) = SavedLocationLightPollutionModel.resolve(key: home, provider: provider) {
            XCTAssertEqual(p.category, .high)
            XCTAssertEqual(p.formattedBrightness, "18.5")
        } else {
            XCTFail("home should be available")
        }
        if case .available(let p) = SavedLocationLightPollutionModel.resolve(key: stub, provider: provider) {
            XCTAssertEqual(p.category, .veryLow)
        } else {
            XCTFail("stub should be available")
        }
        XCTAssertEqual(SavedLocationLightPollutionModel.resolve(key: out, provider: provider), .unavailable)
        XCTAssertEqual(SavedLocationLightPollutionModel.resolve(key: invalid, provider: provider), .unavailable)
        XCTAssertEqual(SavedLocationLightPollutionModel.resolve(key: home, provider: nil), .unavailable)
    }

    func testRenameOnlyIdentityRemainsStable() {
        let id = UUID()
        let keyA = SavedLocationLightPollutionModel.LocationKey(
            id: id, latitude: 45.45, longitude: -122.75
        )
        let keyRenamed = SavedLocationLightPollutionModel.LocationKey(
            id: id, latitude: 45.45, longitude: -122.75
        )
        XCTAssertEqual(keyA, keyRenamed)
        // Name is not part of the key — brightness is not stored on SavedLocation.
        let keyMoved = SavedLocationLightPollutionModel.LocationKey(
            id: id, latitude: 46.0, longitude: -122.75
        )
        XCTAssertNotEqual(keyA, keyMoved)
    }

    // MARK: - Overlapping supersession

    @MainActor
    func testSlowerEarlierRefreshCannotOverwriteNewerResult() async {
        let gate = GatedProviderLoader()
        let model = SavedLocationLightPollutionModel {
            await gate.load()
        }
        let loc = SavedLocation(name: "Home", latitude: 45.45, longitude: -122.75)

        let taskA = Task { await model.refresh(locations: [loc]) }
        await gate.waitUntilEntered(count: 1)

        let taskB = Task { await model.refresh(locations: [loc]) }
        await gate.waitUntilEntered(count: 2)

        // Complete B first with darker sky.
        await gate.releaseNewest(with: FixedBrightnessProvider(value: 21.3))
        await taskB.value

        if case .available(let p) = model.state(for: loc) {
            XCTAssertEqual(p.displayValue, "Very low · 21.3 mag/arcsec²")
        } else {
            XCTFail("expected B result after B completed")
        }

        // Complete slower A with urban brightness — must not overwrite B.
        await gate.releaseOldest(with: FixedBrightnessProvider(value: 18.5))
        await taskA.value

        if case .available(let p) = model.state(for: loc) {
            XCTAssertEqual(p.displayValue, "Very low · 21.3 mag/arcsec²")
            XCTAssertEqual(p.category, .veryLow)
        } else {
            XCTFail("stale A must not wipe B")
        }
    }

    @MainActor
    func testDeletedLocationCannotBeRepublishedByStaleRefresh() async {
        let gate = GatedProviderLoader()
        let model = SavedLocationLightPollutionModel {
            await gate.load()
        }
        let a = SavedLocation(name: "A", latitude: 45.0, longitude: -122.0)
        let b = SavedLocation(name: "B", latitude: 46.0, longitude: -123.0)
        let keyB = SavedLocationLightPollutionModel.LocationKey(location: b)

        let taskA = Task { await model.refresh(locations: [a, b]) }
        await gate.waitUntilEntered(count: 1)

        let taskB = Task { await model.refresh(locations: [a]) }
        await gate.waitUntilEntered(count: 2)

        await gate.releaseNewest(with: FixedBrightnessProvider(value: 19.0))
        await taskB.value

        XCTAssertEqual(model.states.count, 1)
        XCTAssertNil(model.states[keyB])
        XCTAssertNotNil(model.states[SavedLocationLightPollutionModel.LocationKey(location: a)])

        // Stale full-list refresh A completes — must not restore B.
        await gate.releaseOldest(with: FixedBrightnessProvider(value: 19.0))
        await taskA.value

        XCTAssertEqual(model.states.count, 1)
        XCTAssertNil(model.states[keyB])
        XCTAssertNotNil(model.states[SavedLocationLightPollutionModel.LocationKey(location: a)])
    }

    @MainActor
    func testCoordinateChangeCannotRestoreStaleCoordinates() async {
        let gate = GatedProviderLoader()
        let model = SavedLocationLightPollutionModel {
            await gate.load()
        }
        let id = UUID()
        let c1 = SavedLocation(name: "Pin", latitude: 45.0, longitude: -122.0)
        c1.id = id
        let c2 = SavedLocation(name: "Pin", latitude: 46.0, longitude: -123.0)
        c2.id = id
        let keyC1 = SavedLocationLightPollutionModel.LocationKey(location: c1)
        let keyC2 = SavedLocationLightPollutionModel.LocationKey(location: c2)
        XCTAssertNotEqual(keyC1, keyC2)

        let taskA = Task { await model.refresh(locations: [c1]) }
        await gate.waitUntilEntered(count: 1)

        let taskB = Task { await model.refresh(locations: [c2]) }
        await gate.waitUntilEntered(count: 2)

        // B completes with C2 brightness.
        await gate.releaseNewest(with: FixedBrightnessProvider(value: 21.3))
        await taskB.value

        if case .available(let p) = model.state(for: c2) {
            XCTAssertEqual(p.formattedBrightness, "21.3")
        } else {
            XCTFail("C2 should be available after B")
        }
        XCTAssertNil(model.states[keyC1], "C1 key must not remain after wholesale replace")

        // Stale A for C1 completes — must not restore C1 or overwrite C2.
        await gate.releaseOldest(with: FixedBrightnessProvider(value: 18.5))
        await taskA.value

        XCTAssertNil(model.states[keyC1])
        if case .available(let p) = model.state(for: c2) {
            XCTAssertEqual(p.displayValue, "Very low · 21.3 mag/arcsec²")
        } else {
            XCTFail("C2 must remain B after stale A")
        }
        // Current location identity must not expose C1’s urban reading.
        if case .available(let p) = model.state(for: c2) {
            XCTAssertNotEqual(p.formattedBrightness, "18.5")
        }
    }
}

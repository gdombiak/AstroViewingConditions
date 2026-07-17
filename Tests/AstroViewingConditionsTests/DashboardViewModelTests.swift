import SharedCode
import CoreLocation
import XCTest
import Foundation
@testable import AstroViewingConditions

@MainActor
final class DashboardViewModelTests: XCTestCase {

    func testFirstLaunchPersistsExplicitCurrentLocationSelection() {
        let provider = LocationProviderSpy()
        let recorder = SelectionRecorder()
        let loader = DashboardLocationLoader(
            persistedSelection: nil,
            provider: provider,
            saveSelection: recorder.record
        )

        loader.restoreSelection(using: [])

        XCTAssertEqual(loader.selectedLocation.source, .currentGPS)
        XCTAssertEqual(recorder.selections.map(\.source), [.currentGPS])
    }

    func testRestoresPersistedFixedLocation() {
        let saved = makeCachedLocation()
        let persisted = SelectedLocation(
            source: .saved,
            id: saved.id,
            name: "Old name",
            latitude: 0,
            longitude: 0
        )
        let loader = DashboardLocationLoader(
            persistedSelection: persisted,
            provider: LocationProviderSpy(),
            saveSelection: { _ in }
        )

        loader.restoreSelection(using: [saved])

        XCTAssertEqual(loader.selectedLocation.source, .saved)
        XCTAssertEqual(loader.activeLocation?.id, saved.id)
        XCTAssertEqual(loader.activeLocation?.latitude, saved.latitude)
        XCTAssertEqual(loader.activeLocation?.longitude, saved.longitude)
    }

    func testInvalidPersistedFixedLocationRepairsAndPersistsCurrentLocation() {
        let recorder = SelectionRecorder()
        let loader = DashboardLocationLoader(
            persistedSelection: SelectedLocation(
                source: .saved,
                id: UUID(),
                name: "Deleted",
                latitude: 12,
                longitude: 34
            ),
            provider: LocationProviderSpy(),
            saveSelection: recorder.record
        )

        loader.restoreSelection(using: [])

        XCTAssertEqual(loader.selectedLocation.source, .currentGPS)
        XCTAssertEqual(recorder.selections.last?.source, .currentGPS)
    }

    func testFixedSelectionDoesNotResolveCurrentLocationDuringInitialLoading() async {
        let saved = makeCachedLocation()
        let provider = LocationProviderSpy()
        let loader = DashboardLocationLoader(
            persistedSelection: savedSelection(for: saved),
            provider: provider,
            saveSelection: { _ in }
        )

        loader.restoreSelection(using: [saved])
        try? await loader.resolveCurrentLocationIfNeeded()

        XCTAssertEqual(provider.resolveCallCount, 0)
        XCTAssertEqual(provider.authorizationRequestCount, 0)
    }

    func testFixedSelectionIgnoresAuthorizationStatusChanges() async {
        let saved = makeCachedLocation()
        let provider = LocationProviderSpy(authorizationStatus: .notDetermined)
        let loader = DashboardLocationLoader(
            persistedSelection: savedSelection(for: saved),
            provider: provider,
            saveSelection: { _ in }
        )

        provider.authorizationStatus = .authorizedWhenInUse
        try? await loader.resolveCurrentLocationIfNeeded()

        XCTAssertEqual(provider.resolveCallCount, 0)
        XCTAssertEqual(provider.authorizationRequestCount, 0)
    }

    func testSwitchingFromFixedToCurrentLocationResolvesDeviceLocation() async {
        let saved = makeCachedLocation()
        let provider = LocationProviderSpy()
        let loader = DashboardLocationLoader(
            persistedSelection: savedSelection(for: saved),
            provider: provider,
            saveSelection: { _ in }
        )
        loader.restoreSelection(using: [saved])
        loader.select(SelectedLocation(
            source: .currentGPS,
            name: "My Current Location",
            latitude: 0,
            longitude: 0
        ))

        try? await loader.resolveCurrentLocationIfNeeded()

        XCTAssertEqual(provider.resolveCallCount, 1)
        XCTAssertEqual(loader.activeLocation?.latitude, provider.resolvedLocation.latitude)
    }

    func testSwitchingFromCurrentToFixedPreventsLaterGPSResolution() async {
        let saved = makeCachedLocation()
        let provider = LocationProviderSpy()
        let loader = DashboardLocationLoader(
            persistedSelection: nil,
            provider: provider,
            saveSelection: { _ in }
        )
        loader.restoreSelection(using: [saved])
        loader.select(savedSelection(for: saved))

        try? await loader.resolveCurrentLocationIfNeeded()

        XCTAssertEqual(provider.resolveCallCount, 0)
        XCTAssertEqual(provider.authorizationRequestCount, 0)
    }

    func testFieldModeRecreationWithFixedLocationDoesNotResolveDeviceLocation() async {
        let saved = makeCachedLocation()
        let provider = LocationProviderSpy()
        let session = DashboardLocationSession()
        let firstLoader = DashboardLocationLoader(
            persistedSelection: savedSelection(for: saved),
            provider: provider,
            saveSelection: { _ in },
            locationSession: session
        )
        let recreatedLoader = DashboardLocationLoader(
            persistedSelection: savedSelection(for: saved),
            provider: provider,
            saveSelection: { _ in },
            locationSession: session
        )

        firstLoader.restoreSelection(using: [saved])
        try? await firstLoader.resolveCurrentLocationIfNeeded()
        recreatedLoader.restoreSelection(using: [saved])
        try? await recreatedLoader.resolveCurrentLocationIfNeeded()

        XCTAssertEqual(provider.resolveCallCount, 0)
    }

    func testFieldModeRecreationWithResolvedCurrentLocationDoesNotResolveAgain() async {
        let provider = LocationProviderSpy()
        let session = DashboardLocationSession()
        let firstLoader = DashboardLocationLoader(
            persistedSelection: nil,
            provider: provider,
            saveSelection: { _ in },
            locationSession: session
        )
        firstLoader.restoreSelection(using: [])
        try? await firstLoader.resolveCurrentLocationIfNeeded()

        let recreatedLoader = DashboardLocationLoader(
            persistedSelection: firstLoader.selectedLocation,
            provider: provider,
            saveSelection: { _ in },
            locationSession: session
        )

        recreatedLoader.restoreSelection(using: [])
        try? await recreatedLoader.resolveCurrentLocationIfNeeded()

        XCTAssertEqual(provider.resolveCallCount, 1)
        XCTAssertEqual(recreatedLoader.activeLocation?.latitude, provider.resolvedLocation.latitude)
    }

    func testNewSessionWithPersistedCurrentLocationCoordinatesResolvesAgain() async {
        let provider = LocationProviderSpy()
        let loader = DashboardLocationLoader(
            persistedSelection: SelectedLocation(
                source: .currentGPS,
                name: "Previous Session",
                latitude: 45.52,
                longitude: -122.68
            ),
            provider: provider,
            saveSelection: { _ in },
            locationSession: DashboardLocationSession()
        )

        XCTAssertNil(loader.activeLocation)
        try? await loader.resolveCurrentLocationIfNeeded()

        XCTAssertEqual(provider.resolveCallCount, 1)
        XCTAssertEqual(loader.activeLocation?.latitude, provider.resolvedLocation.latitude)
    }

    func testInFlightCurrentLocationResultDoesNotOverwriteLaterFixedSelection() async {
        let fixedLocation = makeCachedLocation()
        let provider = SuspendedLocationProvider()
        let recorder = SelectionRecorder()
        let loader = DashboardLocationLoader(
            persistedSelection: SelectedLocation(
                source: .currentGPS,
                name: "My Current Location",
                latitude: 0,
                longitude: 0
            ),
            provider: provider,
            saveSelection: recorder.record
        )

        let resolution = Task { try? await loader.resolveCurrentLocationIfNeeded() }
        await provider.waitForResolutionRequest()
        loader.select(savedSelection(for: fixedLocation))
        provider.completeResolution()
        await resolution.value

        XCTAssertEqual(loader.selectedLocation.source, .saved)
        XCTAssertEqual(loader.selectedLocation.id, fixedLocation.id)
        XCTAssertFalse(recorder.selections.contains { $0.source == .currentGPS })
    }

    func testStaleCurrentLocationFailureIsSuppressedAfterSwitchingToFixedLocation() async {
        let fixedLocation = makeCachedLocation()
        let provider = SuspendedLocationProvider()
        let recorder = SelectionRecorder()
        let loader = DashboardLocationLoader(
            persistedSelection: SelectedLocation(
                source: .currentGPS,
                name: "My Current Location",
                latitude: 0,
                longitude: 0
            ),
            provider: provider,
            saveSelection: recorder.record
        )

        let resolution = Task { () -> Result<DashboardCurrentLocationResolutionResult, Error> in
            do {
                return .success(try await loader.resolveCurrentLocationIfNeeded())
            } catch {
                return .failure(error)
            }
        }
        await provider.waitForResolutionRequest()
        loader.select(savedSelection(for: fixedLocation))
        provider.failResolution()

        switch await resolution.value {
        case .success:
            break
        case .failure(let error):
            XCTFail("Stale request propagated \(error)")
        }
        XCTAssertEqual(loader.selectedLocation.source, .saved)
        XCTAssertEqual(loader.activeLocation?.id, fixedLocation.id)
        XCTAssertFalse(recorder.selections.contains { $0.source == .currentGPS })
    }

    func testResolvedCurrentLocationMarksInternalSelectionUpdateForSingleLoadPath() async {
        let provider = LocationProviderSpy()
        let loader = DashboardLocationLoader(
            persistedSelection: SelectedLocation(
                source: .currentGPS,
                name: "My Current Location",
                latitude: 0,
                longitude: 0
            ),
            provider: provider,
            saveSelection: { _ in }
        )

        let result = try? await loader.resolveCurrentLocationIfNeeded()

        XCTAssertEqual(result, .resolvedSelectionUpdated)
        XCTAssertTrue(loader.consumeInternallyResolvedSelectionUpdate(matching: loader.selectedLocation))
        XCTAssertFalse(loader.consumeInternallyResolvedSelectionUpdate(matching: loader.selectedLocation))
    }

    func testFixedSelectionIsNotMarkedAsInternalResolutionUpdate() {
        let fixedLocation = makeCachedLocation()
        let loader = DashboardLocationLoader(
            persistedSelection: nil,
            provider: LocationProviderSpy(),
            saveSelection: { _ in }
        )

        loader.select(savedSelection(for: fixedLocation))

        XCTAssertFalse(loader.consumeInternallyResolvedSelectionUpdate(matching: loader.selectedLocation))
    }

    func testConcurrentSameLocationConditionLoadsCoalesce() async {
        let gate = SuspendedWeatherRequestGate()
        let weather = WeatherService { _ in
            await gate.response()
        }
        let viewModel = DashboardViewModel(
            conditionsProvider: ConditionsProvider(weatherService: weather)
        )
        let location = CachedLocation(name: "Coalesced", latitude: 11.123, longitude: 22.456)

        let firstLoad = Task { await viewModel.loadConditionsIfNeeded(for: location) }
        await gate.waitForRequestCount(1)
        let secondLoad = Task { await viewModel.loadConditionsIfNeeded(for: location) }
        await Task.yield()

        let requestsWhileSuspended = await gate.requestCount
        XCTAssertEqual(requestsWhileSuspended, 1)
        await gate.completeRequest()
        await firstLoad.value
        await secondLoad.value

        let finalRequestCount = await gate.requestCount
        XCTAssertEqual(finalRequestCount, 1)
    }

    func testFieldModeRecreationSharesInFlightCurrentLocationResolution() async {
        let session = DashboardLocationSession()
        let provider = SuspendedLocationProvider()
        let firstRecorder = SelectionRecorder()
        let secondRecorder = SelectionRecorder()
        let unresolvedCurrentLocation = SelectedLocation(
            source: .currentGPS,
            name: "My Current Location",
            latitude: 0,
            longitude: 0
        )
        let firstLoader = DashboardLocationLoader(
            persistedSelection: unresolvedCurrentLocation,
            provider: provider,
            saveSelection: firstRecorder.record,
            locationSession: session
        )

        let firstResolution = Task { try? await firstLoader.resolveCurrentLocationIfNeeded() }
        await provider.waitForResolutionRequest()

        let recreatedLoader = DashboardLocationLoader(
            persistedSelection: unresolvedCurrentLocation,
            provider: provider,
            saveSelection: secondRecorder.record,
            locationSession: session
        )
        let secondResolution = Task { try? await recreatedLoader.resolveCurrentLocationIfNeeded() }
        await Task.yield()

        XCTAssertEqual(provider.resolveCallCount, 1)
        provider.completeResolution()
        await firstResolution.value
        await secondResolution.value

        XCTAssertEqual(firstLoader.activeLocation?.latitude, provider.resolvedLocation.latitude)
        XCTAssertEqual(recreatedLoader.activeLocation?.latitude, provider.resolvedLocation.latitude)
        XCTAssertEqual(firstRecorder.selections.count, 1)
        XCTAssertEqual(secondRecorder.selections.count, 1)
        XCTAssertFalse(firstRecorder.selections.contains { $0.latitude == 0 && $0.longitude == 0 })
        XCTAssertFalse(secondRecorder.selections.contains { $0.latitude == 0 && $0.longitude == 0 })
    }

    func testFailedSharedResolutionClearsSessionOperationForRetry() async {
        let provider = FailingThenSucceedingLocationProvider()
        let loader = DashboardLocationLoader(
            persistedSelection: SelectedLocation(
                source: .currentGPS,
                name: "My Current Location",
                latitude: 0,
                longitude: 0
            ),
            provider: provider,
            saveSelection: { _ in },
            locationSession: DashboardLocationSession()
        )

        do {
            try await loader.resolveCurrentLocationIfNeeded()
            XCTFail("Expected the first resolution to fail")
        } catch {
            // Expected.
        }
        try? await loader.resolveCurrentLocationIfNeeded()

        XCTAssertEqual(provider.resolveCallCount, 2)
        XCTAssertEqual(loader.activeLocation?.latitude, provider.resolvedLocation.latitude)
    }

    func testPostInvalidationResolutionDoesNotReuseObsoleteSharedRequest() async {
        let session = DashboardLocationSession()
        let provider = MultiSuspendedLocationProvider()
        let recorder = SelectionRecorder()
        let fixedLocation = makeCachedLocation()
        let loader = DashboardLocationLoader(
            persistedSelection: SelectedLocation(
                source: .currentGPS,
                name: "My Current Location",
                latitude: 0,
                longitude: 0
            ),
            provider: provider,
            saveSelection: recorder.record,
            locationSession: session
        )

        let requestA = Task { try? await loader.resolveCurrentLocationIfNeeded() }
        await provider.waitForRequest(count: 1)

        loader.select(savedSelection(for: fixedLocation))
        loader.select(SelectedLocation(
            source: .currentGPS,
            name: "My Current Location",
            latitude: 0,
            longitude: 0
        ))
        let requestB = Task { try? await loader.resolveCurrentLocationIfNeeded() }
        await provider.waitForRequest(count: 2)

        XCTAssertEqual(provider.resolveCallCount, 2)
        provider.completeRequest(at: 0, with: CachedLocation(
            name: "Obsolete A",
            latitude: 10,
            longitude: 20
        ))
        await requestA.value

        XCTAssertNil(loader.activeLocation)
        XCTAssertFalse(recorder.selections.contains { $0.name == "Obsolete A" })

        provider.completeRequest(at: 1, with: CachedLocation(
            name: "Fresh B",
            latitude: 30,
            longitude: 40
        ))
        await requestB.value

        XCTAssertEqual(loader.activeLocation?.name, "Fresh B")
        XCTAssertEqual(loader.activeLocation?.latitude, 30)
        XCTAssertEqual(loader.activeLocation?.longitude, 40)
        XCTAssertEqual(recorder.selections.last?.name, "Fresh B")
        XCTAssertEqual(provider.resolveCallCount, 2)
    }

    func testReturningFromFixedLocationToCurrentLocationResolvesAgain() async {
        let fixedLocation = makeCachedLocation()
        let provider = LocationProviderSpy()
        let loader = DashboardLocationLoader(
            persistedSelection: nil,
            provider: provider,
            saveSelection: { _ in }
        )

        loader.restoreSelection(using: [fixedLocation])
        try? await loader.resolveCurrentLocationIfNeeded()
        loader.select(savedSelection(for: fixedLocation))
        loader.select(SelectedLocation(
            source: .currentGPS,
            name: "My Current Location",
            latitude: 0,
            longitude: 0
        ))
        try? await loader.resolveCurrentLocationIfNeeded()

        XCTAssertEqual(provider.resolveCallCount, 2)
    }

    func testRehydratedCurrentLocationAtEquatorIsResolved() {
        let provider = LocationProviderSpy()
        let session = DashboardLocationSession()
        session.currentLocation = CachedLocation(name: "Equator", latitude: 0, longitude: 10)
        let loader = DashboardLocationLoader(
            persistedSelection: SelectedLocation(
                source: .currentGPS,
                name: "Equator",
                latitude: 0,
                longitude: 10
            ),
            provider: provider,
            saveSelection: { _ in },
            locationSession: session
        )

        XCTAssertEqual(loader.activeLocation?.latitude, 0)
        XCTAssertEqual(loader.activeLocation?.longitude, 10)
        XCTAssertEqual(provider.resolveCallCount, 0)
    }

    func testRehydratedCurrentLocationOnPrimeMeridianIsResolved() {
        let provider = LocationProviderSpy()
        let session = DashboardLocationSession()
        session.currentLocation = CachedLocation(name: "Prime Meridian", latitude: 10, longitude: 0)
        let loader = DashboardLocationLoader(
            persistedSelection: SelectedLocation(
                source: .currentGPS,
                name: "Prime Meridian",
                latitude: 10,
                longitude: 0
            ),
            provider: provider,
            saveSelection: { _ in },
            locationSession: session
        )

        XCTAssertEqual(loader.activeLocation?.latitude, 10)
        XCTAssertEqual(loader.activeLocation?.longitude, 0)
        XCTAssertEqual(provider.resolveCallCount, 0)
    }

    func testPlaceholderCurrentLocationRemainsUnresolved() {
        let loader = DashboardLocationLoader(
            persistedSelection: SelectedLocation(
                source: .currentGPS,
                name: "My Current Location",
                latitude: 0,
                longitude: 0
            ),
            provider: LocationProviderSpy(),
            saveSelection: { _ in }
        )

        XCTAssertNil(loader.activeLocation)
    }

    func testReselectingCurrentLocationPreservesResolvedSelectionWithoutGPSRequest() async {
        let provider = LocationProviderSpy()
        let recorder = SelectionRecorder()
        let session = DashboardLocationSession()
        session.currentLocation = CachedLocation(name: "Portland", latitude: 45.52, longitude: -122.68)
        let loader = DashboardLocationLoader(
            persistedSelection: SelectedLocation(
                source: .currentGPS,
                name: "Portland",
                latitude: 45.52,
                longitude: -122.68
            ),
            provider: provider,
            saveSelection: recorder.record,
            locationSession: session
        )

        loader.select(SelectedLocation(
            source: .currentGPS,
            name: "My Current Location",
            latitude: 0,
            longitude: 0
        ))
        try? await loader.resolveCurrentLocationIfNeeded()

        XCTAssertEqual(loader.selectedLocation.name, "Portland")
        XCTAssertEqual(loader.selectedLocation.latitude, 45.52)
        XCTAssertEqual(loader.selectedLocation.longitude, -122.68)
        XCTAssertEqual(loader.activeLocation?.latitude, 45.52)
        XCTAssertEqual(loader.activeLocation?.longitude, -122.68)
        XCTAssertFalse(recorder.selections.contains { $0.latitude == 0 && $0.longitude == 0 })
        XCTAssertEqual(provider.resolveCallCount, 0)
    }

    func testDeletingSelectedFixedLocationClearsCurrentCacheAndResolvesAgain() async {
        let fixedLocation = makeCachedLocation()
        let provider = LocationProviderSpy()
        let recorder = SelectionRecorder()
        let session = DashboardLocationSession()
        session.currentLocation = CachedLocation(name: "Previous GPS Result", latitude: 40, longitude: -120)
        let loader = DashboardLocationLoader(
            persistedSelection: SelectedLocation(
                source: .currentGPS,
                name: "Previous GPS Result",
                latitude: 40,
                longitude: -120
            ),
            provider: provider,
            saveSelection: recorder.record,
            locationSession: session
        )

        loader.select(savedSelection(for: fixedLocation))
        loader.repairSelectionIfNeeded(using: [])

        XCTAssertEqual(loader.selectedLocation.source, .currentGPS)
        XCTAssertNil(loader.activeLocation)

        try? await loader.resolveCurrentLocationIfNeeded()

        XCTAssertEqual(provider.resolveCallCount, 1)
        XCTAssertEqual(loader.activeLocation?.latitude, provider.resolvedLocation.latitude)
        XCTAssertEqual(loader.activeLocation?.longitude, provider.resolvedLocation.longitude)
        XCTAssertEqual(recorder.selections.last?.source, .currentGPS)
        XCTAssertEqual(recorder.selections.last?.latitude, provider.resolvedLocation.latitude)
        XCTAssertEqual(recorder.selections.last?.longitude, provider.resolvedLocation.longitude)
    }

    private func makeCachedLocation() -> CachedLocation {
        CachedLocation(id: UUID(), name: "Portland", latitude: 45.52, longitude: -122.68)
    }

    private func savedSelection(for location: CachedLocation) -> SelectedLocation {
        SelectedLocation(
            source: .saved,
            id: location.id,
            name: location.name,
            latitude: location.latitude,
            longitude: location.longitude
        )
    }

    func testTimeoutStopsInitialLoadingAndShowsError() async {
        let viewModel = makeTimeoutViewModel()
        let location = SavedLocation(name: "Test", latitude: 45, longitude: -122)

        let succeeded = await viewModel.refresh(for: location)

        XCTAssertFalse(succeeded)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.viewingConditions)
        XCTAssertEqual(viewModel.error?.localizedDescription, "Weather request timed out. Please try again.")
    }

    func testRefreshTimeoutKeepsExistingConditionsAndShowsSavedDataWarning() async {
        let viewModel = makeTimeoutViewModel()
        let location = SavedLocation(name: "Test", latitude: 45, longitude: -122)
        let existing = ViewingConditions(
            fetchedAt: Date(),
            location: CachedLocation(from: location),
            hourlyForecasts: [],
            dailySunEvents: [],
            dailyMoonInfo: [],
            issPasses: [],
            fogScore: FogScore(score: 0, factors: [])
        )
        viewModel.viewingConditions = existing

        let succeeded = await viewModel.refresh(for: location)

        XCTAssertFalse(succeeded)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.viewingConditions?.fetchedAt, existing.fetchedAt)
        XCTAssertEqual(viewModel.error?.localizedDescription, "Refresh timed out. Showing saved data.")
    }

    private func makeTimeoutViewModel() -> DashboardViewModel {
        let weather = WeatherService(forecastTimeout: 0.01) { _ in
            await withUnsafeContinuation { (_: UnsafeContinuation<Void, Never>) in }
            throw CancellationError()
        }
        return DashboardViewModel(conditionsProvider: ConditionsProvider(weatherService: weather))
    }

    func testTargetSheetWidthOnlyExpandsForRegularSizeClass() {
        XCTAssertEqual(TargetSheetLayout.preferredWidth(for: .regular), 720)
        XCTAssertNil(TargetSheetLayout.preferredWidth(for: .compact))
        XCTAssertNil(TargetSheetLayout.preferredWidth(for: nil))
    }

    func testISSCardTitleIsConsistentAcrossDaySelections() {
        let viewModel = DashboardViewModel()

        for day in DashboardViewModel.DaySelection.allCases {
            viewModel.selectedDay = day
            XCTAssertEqual(viewModel.issCardTitle, "ISS Passes")
        }
    }

    func testBestTargetsPoorConditionsNoteThreshold() {
        XCTAssertTrue(TonightsBestTargetsCard.showsPoorConditionsNote(for: 29))
        XCTAssertFalse(TonightsBestTargetsCard.showsPoorConditionsNote(for: 30))
        XCTAssertFalse(TonightsBestTargetsCard.showsPoorConditionsNote(for: nil))
    }

    func testBestTargetsDashboardCapsAtFiveAndShowsViewAllForAdditionalTargets() {
        let recommendations = [90, 85, 80, 75, 70, 65].enumerated().map { index, score in
            Self.makeRecommendation(id: "target-\(index)", name: "Target \(index)", score: score)
        }
        let presentation = BestTargetsListPresentation(recommendations: recommendations)

        XCTAssertEqual(presentation.dashboardRecommendations.count, 5)
        XCTAssertTrue(presentation.hasAdditionalTargets)
        XCTAssertTrue(TonightsBestTargetsCard.showsViewAll(hasAdditionalTargets: true))
        XCTAssertFalse(TonightsBestTargetsCard.showsViewAll(hasAdditionalTargets: false))
    }

    func testBestTargetsFullListGroupsScoreBandsAndHidesScoresBelow45() {
        let recommendations = [90, 80, 79, 65, 64, 45, 44].enumerated().map { index, score in
            Self.makeRecommendation(id: "target-\(index)", name: "Target \(index)", score: score)
        }
        let sections = BestTargetsListPresentation(recommendations: recommendations).sections(for: .all)

        XCTAssertEqual(sections.map(\.band), [.excellent, .good, .fair])
        XCTAssertEqual(sections.map { $0.recommendations.map(\.score) }, [
            [90, 80],
            [79, 65],
            [64, 45]
        ])
        XCTAssertFalse(sections.flatMap(\.recommendations).contains { $0.score < 45 })
    }

    func testCurrentTargetRecommendationsUseInjectedServiceOutput() {
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let referenceDate = calendar.date(from: DateComponents(
            year: 2026, month: 6, day: 29, hour: 12
        ))!
        let startOfDay = calendar.startOfDay(for: referenceDate)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let sunEvents = [
            Self.makeSunEvents(for: startOfDay, calendar: calendar),
            Self.makeSunEvents(for: tomorrow, calendar: calendar)
        ]
        let forecasts = (20...28).map { hour -> HourlyForecast in
            let date = calendar.date(
                bySettingHour: hour % 24,
                minute: 0,
                second: 0,
                of: hour >= 24 ? tomorrow : startOfDay
            )!
            return Self.makeForecast(at: date)
        }
        let expectedRecommendations = [
            Self.makeRecommendation(id: "saturn", name: "Saturn", score: 65),
            Self.makeRecommendation(id: "venus", name: "Venus", score: 62),
            Self.makeRecommendation(id: "jupiter", name: "Jupiter", score: 53),
            Self.makeRecommendation(id: "mars", name: "Mars", score: 45)
        ]
        let targetRecommendationService = FixedDashboardTargetRecommendationService(
            recommendations: expectedRecommendations
        )
        let viewModel = DashboardViewModel(
            targetRecommendationService: targetRecommendationService,
            now: { referenceDate }
        )
        viewModel.viewingConditions = ViewingConditions(
            fetchedAt: referenceDate,
            location: CachedLocation(name: "Cupertino", latitude: 37.323, longitude: -122.0322, elevation: 72),
            hourlyForecasts: forecasts,
            dailySunEvents: sunEvents,
            dailyMoonInfo: [
                MoonInfo(phase: 0.98, phaseName: "Full Moon", altitude: 20, illumination: 98, emoji: ""),
                MoonInfo(phase: 0.99, phaseName: "Full Moon", altitude: 18, illumination: 99, emoji: "")
            ],
            issPasses: [],
            fogScore: FogScore(score: 0, factors: []),
            timeZoneIdentifier: timeZone.identifier
        )

        let recommendations = viewModel.currentTargetRecommendations

        XCTAssertEqual(recommendations.map(\.target.name), ["Saturn", "Venus", "Jupiter", "Mars"])
        XCTAssertEqual(recommendations.map(\.score), [65, 62, 53, 45])
        XCTAssertEqual(targetRecommendationService.requestedLimits, [100])
    }

    func testCurrentISSPassesFollowSelectedLocationDay() {
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let firstDay = calendar.date(from: DateComponents(
            year: 2026, month: 6, day: 28, hour: 12
        ))!
        let startOfFirstDay = calendar.startOfDay(for: firstDay)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfFirstDay)!
        let dayAfter = calendar.date(byAdding: .day, value: 2, to: startOfFirstDay)!
        let fourthDay = calendar.date(byAdding: .day, value: 3, to: startOfFirstDay)!
        let sunEvents = [startOfFirstDay, tomorrow, dayAfter, fourthDay].map {
            Self.makeSunEvents(for: $0, calendar: calendar)
        }
        let tonightBeforeMidnight = calendar.date(
            bySettingHour: 22, minute: 0, second: 0, of: startOfFirstDay
        )!
        let tonightAfterMidnight = calendar.date(
            bySettingHour: 2, minute: 28, second: 0, of: tomorrow
        )!
        let tomorrowNight = calendar.date(
            bySettingHour: 22, minute: 0, second: 0, of: tomorrow
        )!
        let dayAfterNight = calendar.date(
            bySettingHour: 22, minute: 0, second: 0, of: dayAfter
        )!
        let conditions = ViewingConditions(
            fetchedAt: firstDay,
            location: CachedLocation(name: "Test", latitude: 34, longitude: -118, elevation: 0),
            hourlyForecasts: [Self.makeForecast(at: firstDay)],
            dailySunEvents: sunEvents,
            dailyMoonInfo: [],
            issPasses: [
                ISSPass(riseTime: tonightBeforeMidnight, duration: 300, maxElevation: 30),
                ISSPass(riseTime: tonightAfterMidnight, duration: 300, maxElevation: 35),
                ISSPass(riseTime: tomorrowNight, duration: 300, maxElevation: 40),
                ISSPass(riseTime: dayAfterNight, duration: 300, maxElevation: 50)
            ],
            fogScore: FogScore(score: 0, factors: []),
            timeZoneIdentifier: timeZone.identifier
        )
        let viewModel = DashboardViewModel(now: { firstDay })
        viewModel.viewingConditions = conditions

        XCTAssertEqual(viewModel.currentISSPasses.map(\.maxElevation), [30, 35])
        viewModel.selectedDay = .tomorrow
        XCTAssertEqual(viewModel.currentISSPasses.map(\.maxElevation), [40])
        viewModel.selectedDay = .dayAfter
        XCTAssertEqual(viewModel.currentISSPasses.map(\.maxElevation), [50])
    }

    private static func makeForecast(at date: Date) -> HourlyForecast {
        HourlyForecast(
            time: date,
            cloudCover: 0,
            humidity: 0,
            windSpeed: 0,
            windDirection: 0,
            temperature: 0
        )
    }

    private static func makeSunEvents(for date: Date, calendar: Calendar) -> SunEvents {
        let sunrise = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: date)!
        let sunset = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: date)!
        return SunEvents(
            sunrise: sunrise,
            sunset: sunset,
            civilTwilightBegin: sunrise.addingTimeInterval(-1_800),
            civilTwilightEnd: sunset.addingTimeInterval(1_800),
            nauticalTwilightBegin: sunrise.addingTimeInterval(-3_600),
            nauticalTwilightEnd: sunset.addingTimeInterval(3_600),
            astronomicalTwilightBegin: sunrise.addingTimeInterval(-5_400),
            astronomicalTwilightEnd: sunset.addingTimeInterval(5_400)
        )
    }

    private static func makeRecommendation(
        id: String,
        name: String,
        score: Int
    ) -> TargetRecommendation {
        let start = Date(timeIntervalSince1970: 1_782_790_000)
        let end = start.addingTimeInterval(3_600)
        return TargetRecommendation(
            target: ObservableTarget(
                id: id,
                name: name,
                type: .planet,
                preferredEquipment: .nakedEye,
                difficulty: 0.2
            ),
            score: score,
            visibilityWindow: TargetVisibilityWindow(
                start: start,
                end: end,
                bestTime: start.addingTimeInterval(1_800),
                maxAltitude: 35,
                direction: "SE"
            ),
            reasons: [.convenientPlanetWindow],
            summary: "\(name) summary"
        )
    }

    func testScenario1_at11PM_tabLabelsMatchData() {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        
        var monday11PM = DateComponents()
        monday11PM.year = 2026
        monday11PM.month = 2
        monday11PM.day = 22
        monday11PM.hour = 23
        monday11PM.minute = 0
        let fetchDate = calendar.date(from: monday11PM)!
        
        let location = CachedLocation(
            name: "Test",
            latitude: 45.0,
            longitude: -122.0,
            elevation: 100
        )
        
        var forecasts: [HourlyForecast] = []
        for hourOffset in 0..<72 {
            let time = calendar.date(byAdding: .hour, value: hourOffset, to: fetchDate)!
            forecasts.append(HourlyForecast(
                time: time,
                cloudCover: 50,
                humidity: 80,
                windSpeed: 10.0,
                windDirection: 180,
                temperature: 15.0,
                dewPoint: 12.0,
                visibility: 10000,
                lowCloudCover: 30
            ))
        }
        
        let conditions = ViewingConditions(
            fetchedAt: fetchDate,
            location: location,
            hourlyForecasts: forecasts,
            dailySunEvents: [
                SunEvents(
                    sunrise: fetchDate,
                    sunset: fetchDate.addingTimeInterval(43200),
                    civilTwilightBegin: fetchDate.addingTimeInterval(-1800),
                    civilTwilightEnd: fetchDate.addingTimeInterval(45000),
                    nauticalTwilightBegin: fetchDate.addingTimeInterval(-3600),
                    nauticalTwilightEnd: fetchDate.addingTimeInterval(46800),
                    astronomicalTwilightBegin: fetchDate.addingTimeInterval(-5400),
                    astronomicalTwilightEnd: fetchDate.addingTimeInterval(48600)
                )
            ],
            dailyMoonInfo: [
                MoonInfo(
                    phase: 0.5,
                    phaseName: "Full Moon",
                    altitude: 45.0,
                    illumination: 100,
                    emoji: "🌕"
                )
            ],
            issPasses: [],
            fogScore: FogScore(score: 25, factors: [])
        )
        
        let viewModel = DashboardViewModel(now: { fetchDate })
        viewModel.viewingConditions = conditions
        viewModel.lastSuccessfulFetch = fetchDate
        
        let currentDay2Date = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: fetchDate))!
        let actualDay2Title = viewModel.titleForSelectedDay(.dayAfter)
        let currentDay2Formatted = DateFormatters.shortDateFormatter.string(from: currentDay2Date)
        
        XCTAssertEqual(actualDay2Title, currentDay2Formatted, 
            "Tab 2 label should be based on current date, not fetch date")
        
        viewModel.selectedDay = .dayAfter
        let day2Forecasts = viewModel.currentHourlyForecasts
        
        XCTAssertFalse(day2Forecasts.isEmpty, "Tab 2 should have forecasts")
        
        // Forecasts are based on fetch date, not current date
        let fetchDay2Date = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: fetchDate))!
        if let firstForecast = day2Forecasts.first {
            let forecastDate = calendar.startOfDay(for: firstForecast.time)
            XCTAssertEqual(forecastDate, fetchDay2Date,
                "Tab 2 forecasts should be for the day after tomorrow based on fetch date")
        }
    }
    
    func testAt1AMStaleCacheTabsRemainAnchoredToCurrentDate() {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        
        var monday11PM = DateComponents()
        monday11PM.year = 2026
        monday11PM.month = 2
        monday11PM.day = 22
        monday11PM.hour = 23
        monday11PM.minute = 0
        let fetchDate = calendar.date(from: monday11PM)!
        
        var tuesday1AM = DateComponents()
        tuesday1AM.year = 2026
        tuesday1AM.month = 2
        tuesday1AM.day = 23
        tuesday1AM.hour = 1
        tuesday1AM.minute = 0
        let currentDate = calendar.date(from: tuesday1AM)!
        
        let location = CachedLocation(
            name: "Test",
            latitude: 45.0,
            longitude: -122.0,
            elevation: 100
        )
        
        var forecasts: [HourlyForecast] = []
        for hourOffset in 0..<72 {
            let time = calendar.date(byAdding: .hour, value: hourOffset, to: fetchDate)!
            forecasts.append(HourlyForecast(
                time: time,
                cloudCover: 50,
                humidity: 80,
                windSpeed: 10.0,
                windDirection: 180,
                temperature: 15.0,
                dewPoint: 12.0,
                visibility: 10000,
                lowCloudCover: 30
            ))
        }
        
        let conditions = ViewingConditions(
            fetchedAt: fetchDate,
            location: location,
            hourlyForecasts: forecasts,
            dailySunEvents: [
                SunEvents(
                    sunrise: fetchDate,
                    sunset: fetchDate.addingTimeInterval(43200),
                    civilTwilightBegin: fetchDate.addingTimeInterval(-1800),
                    civilTwilightEnd: fetchDate.addingTimeInterval(45000),
                    nauticalTwilightBegin: fetchDate.addingTimeInterval(-3600),
                    nauticalTwilightEnd: fetchDate.addingTimeInterval(46800),
                    astronomicalTwilightBegin: fetchDate.addingTimeInterval(-5400),
                    astronomicalTwilightEnd: fetchDate.addingTimeInterval(48600)
                )
            ],
            dailyMoonInfo: [
                MoonInfo(
                    phase: 0.5,
                    phaseName: "Full Moon",
                    altitude: 45.0,
                    illumination: 100,
                    emoji: "🌕"
                )
            ],
            issPasses: [],
            fogScore: FogScore(score: 25, factors: [])
        )
        
        let viewModel = DashboardViewModel(now: { currentDate })
        viewModel.viewingConditions = conditions
        viewModel.lastSuccessfulFetch = fetchDate
        
        // Tab labels use current date, not fetch date
        let currentDay2Date = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: currentDate))!
        let currentDay2Formatted = DateFormatters.shortDateFormatter.string(from: currentDay2Date)
        
        let actualDay2Title = viewModel.titleForSelectedDay(.dayAfter)
        XCTAssertEqual(actualDay2Title, currentDay2Formatted, 
            "Tab 2 label should be based on current date, not fetch date")
        
        viewModel.selectedDay = .dayAfter
        let day2Forecasts = viewModel.currentHourlyForecasts
        
        XCTAssertFalse(day2Forecasts.isEmpty, "Tab 2 should have forecasts for two days after the current date")
        
        if let firstForecast = day2Forecasts.first {
            let forecastDate = calendar.startOfDay(for: firstForecast.time)
            XCTAssertEqual(forecastDate, calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: currentDate))!,
                "Tab 2 forecasts should be based on the current date, not a stale cache date")
        }
        
        viewModel.selectedDay = .today
        let todayForecasts = viewModel.currentHourlyForecasts
        XCTAssertFalse(todayForecasts.isEmpty, "Tab 0 (Today) should use the actual current day")
        
        if let firstTodayForecast = todayForecasts.first {
            let forecastDate = calendar.startOfDay(for: firstTodayForecast.time)
            XCTAssertEqual(forecastDate, calendar.startOfDay(for: currentDate),
                "Tab 0 forecasts should not remain pinned to a stale cache's first day")
        }
    }
    
    func testScenario1_afterRefresh_labelsAndDataShouldMatchNewFetchDate() {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        
        var tuesday1AM = DateComponents()
        tuesday1AM.year = 2026
        tuesday1AM.month = 2
        tuesday1AM.day = 23
        tuesday1AM.hour = 1
        tuesday1AM.minute = 0
        let refreshDate = calendar.date(from: tuesday1AM)!
        
        let location = CachedLocation(
            name: "Test",
            latitude: 45.0,
            longitude: -122.0,
            elevation: 100
        )
        
        var forecasts: [HourlyForecast] = []
        for hourOffset in 0..<72 {
            let time = calendar.date(byAdding: .hour, value: hourOffset, to: refreshDate)!
            forecasts.append(HourlyForecast(
                time: time,
                cloudCover: 50,
                humidity: 80,
                windSpeed: 10.0,
                windDirection: 180,
                temperature: 15.0,
                dewPoint: 12.0,
                visibility: 10000,
                lowCloudCover: 30
            ))
        }
        
        let conditions = ViewingConditions(
            fetchedAt: refreshDate,
            location: location,
            hourlyForecasts: forecasts,
            dailySunEvents: [
                SunEvents(
                    sunrise: refreshDate,
                    sunset: refreshDate.addingTimeInterval(43200),
                    civilTwilightBegin: refreshDate.addingTimeInterval(-1800),
                    civilTwilightEnd: refreshDate.addingTimeInterval(45000),
                    nauticalTwilightBegin: refreshDate.addingTimeInterval(-3600),
                    nauticalTwilightEnd: refreshDate.addingTimeInterval(46800),
                    astronomicalTwilightBegin: refreshDate.addingTimeInterval(-5400),
                    astronomicalTwilightEnd: refreshDate.addingTimeInterval(48600)
                )
            ],
            dailyMoonInfo: [
                MoonInfo(
                    phase: 0.5,
                    phaseName: "Full Moon",
                    altitude: 45.0,
                    illumination: 100,
                    emoji: "🌕"
                )
            ],
            issPasses: [],
            fogScore: FogScore(score: 25, factors: [])
        )
        
        let viewModel = DashboardViewModel(now: { refreshDate })
        viewModel.viewingConditions = conditions
        viewModel.lastSuccessfulFetch = refreshDate
        
        // Tab labels use current date, not refresh date
        let refreshStartOfDay0 = calendar.startOfDay(for: refreshDate)
        let currentDay2Date = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: refreshDate))!
        let currentDay2Formatted = DateFormatters.shortDateFormatter.string(from: currentDay2Date)
        
        let actualDay2Title = viewModel.titleForSelectedDay(.dayAfter)
        XCTAssertEqual(actualDay2Title, currentDay2Formatted, 
            "Tab 2 label should be based on current date, not refresh date")
        
        viewModel.selectedDay = .dayAfter
        let day2Forecasts = viewModel.currentHourlyForecasts
        
        XCTAssertFalse(day2Forecasts.isEmpty, "Tab 2 should have forecasts after refresh")
        
        if let firstForecast = day2Forecasts.first {
            let forecastDate = calendar.startOfDay(for: firstForecast.time)
            XCTAssertEqual(forecastDate, calendar.date(byAdding: .day, value: 2, to: refreshStartOfDay0)!,
                "Tab 2 forecasts should be for day after tomorrow based on refresh date")
        }
        
        viewModel.selectedDay = .today
        let todayForecasts = viewModel.currentHourlyForecasts
        XCTAssertFalse(todayForecasts.isEmpty, "Tab 0 should have forecasts after refresh")
        
        if let firstTodayForecast = todayForecasts.first {
            let forecastDate = calendar.startOfDay(for: firstTodayForecast.time)
            XCTAssertEqual(forecastDate, refreshStartOfDay0,
                "Tab 0 forecasts should be for refresh date")
        }
    }
}

@MainActor
private final class LocationProviderSpy: DashboardCurrentLocationProviding {
    var authorizationStatus: CLAuthorizationStatus
    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }
    var authorizationRequestCount = 0
    var resolveCallCount = 0
    let resolvedLocation = CachedLocation(name: "Portland", latitude: 45.52, longitude: -122.68)

    init(authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse) {
        self.authorizationStatus = authorizationStatus
    }

    func requestAuthorization() {
        authorizationRequestCount += 1
    }

    func resolveCurrentLocation() async throws -> CachedLocation {
        resolveCallCount += 1
        return resolvedLocation
    }
}

@MainActor
private final class SuspendedLocationProvider: DashboardCurrentLocationProviding {
    var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    var isAuthorized: Bool { true }
    private(set) var resolveCallCount = 0
    let resolvedLocation = CachedLocation(name: "GPS Result", latitude: 45.52, longitude: -122.68)

    private var requestStarted = false
    private var requestStartContinuation: CheckedContinuation<Void, Never>?
    private var resolutionContinuation: CheckedContinuation<CachedLocation, Never>?

    func requestAuthorization() {}

    func resolveCurrentLocation() async throws -> CachedLocation {
        resolveCallCount += 1
        requestStarted = true
        requestStartContinuation?.resume()
        requestStartContinuation = nil

        return await withCheckedContinuation { continuation in
            resolutionContinuation = continuation
        }
    }

    func waitForResolutionRequest() async {
        guard !requestStarted else { return }
        await withCheckedContinuation { continuation in
            requestStartContinuation = continuation
        }
    }

    func completeResolution() {
        resolutionContinuation?.resume(returning: resolvedLocation)
        resolutionContinuation = nil
    }

    func failResolution() {
        resolutionContinuation?.resume(throwing: LocationError.locationUnavailable)
        resolutionContinuation = nil
    }
}

@MainActor
private final class FailingThenSucceedingLocationProvider: DashboardCurrentLocationProviding {
    var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    var isAuthorized: Bool { true }
    private(set) var resolveCallCount = 0
    let resolvedLocation = CachedLocation(name: "Retry Result", latitude: 47.61, longitude: -122.33)

    func requestAuthorization() {}

    func resolveCurrentLocation() async throws -> CachedLocation {
        resolveCallCount += 1
        if resolveCallCount == 1 {
            throw LocationError.locationUnavailable
        }
        return resolvedLocation
    }
}

@MainActor
private final class MultiSuspendedLocationProvider: DashboardCurrentLocationProviding {
    var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    var isAuthorized: Bool { true }
    private(set) var resolveCallCount = 0
    private var requestCountContinuation: CheckedContinuation<Void, Never>?
    private var resolutionContinuations: [CheckedContinuation<CachedLocation, Never>] = []

    func requestAuthorization() {}

    func resolveCurrentLocation() async throws -> CachedLocation {
        resolveCallCount += 1
        requestCountContinuation?.resume()
        requestCountContinuation = nil

        return await withCheckedContinuation { continuation in
            resolutionContinuations.append(continuation)
        }
    }

    func waitForRequest(count: Int) async {
        guard resolveCallCount < count else { return }
        await withCheckedContinuation { continuation in
            requestCountContinuation = continuation
        }
    }

    func completeRequest(at index: Int, with location: CachedLocation) {
        resolutionContinuations[index].resume(returning: location)
    }
}

private actor SuspendedWeatherRequestGate {
    private var completed = false
    private var requestContinuation: CheckedContinuation<Void, Never>?
    private var completionContinuation: CheckedContinuation<Void, Never>?
    private(set) var requestCount = 0

    func response() async throws -> (Data, URLResponse) {
        requestCount += 1
        requestContinuation?.resume()
        requestContinuation = nil

        if !completed {
            await withCheckedContinuation { continuation in
                completionContinuation = continuation
            }
        }

        let data = Data(
            """
            {"utc_offset_seconds":0,"timezone":"UTC","hourly":{"time":["2026-07-17T00:00"],"cloudcover":[0],"relativehumidity_2m":[50],"windspeed_10m":[1.0],"winddirection_10m":[0],"temperature_2m":[10.0]}}
            """.utf8
        )
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com/forecast")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }

    func waitForRequestCount(_ count: Int) async {
        guard requestCount < count else { return }
        await withCheckedContinuation { continuation in
            requestContinuation = continuation
        }
    }

    func completeRequest() {
        completed = true
        completionContinuation?.resume()
        completionContinuation = nil
    }
}

@MainActor
private final class SelectionRecorder {
    private(set) var selections: [SelectedLocation] = []

    func record(_ selection: SelectedLocation) {
        selections.append(selection)
    }
}

private final class FixedDashboardTargetRecommendationService: TargetRecommendationProviding, @unchecked Sendable {
    let recommendations: [TargetRecommendation]
    private(set) var requestedLimits: [Int] = []

    init(recommendations: [TargetRecommendation]) {
        self.recommendations = recommendations
    }

    func recommendations(
        for context: TargetRecommendationContext,
        limit: Int
    ) -> [TargetRecommendation] {
        requestedLimits.append(limit)
        return Array(recommendations.prefix(limit))
    }
}

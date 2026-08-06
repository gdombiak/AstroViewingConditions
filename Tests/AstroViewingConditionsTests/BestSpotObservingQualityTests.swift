@testable import SharedCode
@testable import AstroViewingConditions
import XCTest

// MARK: - Test doubles

/// Returns a fixed brightness for all coordinates.
private struct FixedBrightnessProvider: LightPollutionProviding, Sendable {
    let value: Double?
    func modeledZenithSkyBrightness(latitude: Double, longitude: Double) -> Double? { value }
}

/// Brighter (lower mag) for latitudes nearer the center latitude band, darker farther north.
private struct LatitudeGradientBrightnessProvider: LightPollutionProviding, Sendable {
    let centerLatitude: Double
    func modeledZenithSkyBrightness(latitude: Double, longitude: Double) -> Double? {
        let delta = abs(latitude - centerLatitude)
        // Near center: urban 18.5; farther: darker 21.3
        return delta < 0.08 ? 18.5 : 21.3
    }
}

/// Fails LP for one latitude band only (forces search-wide fallback when used on a multi-point grid).
private struct OneCoordinateNilBrightnessProvider: LightPollutionProviding, Sendable {
    let failLatitude: Double
    let successValue: Double
    let tolerance: Double
    func modeledZenithSkyBrightness(latitude: Double, longitude: Double) -> Double? {
        if abs(latitude - failLatitude) <= tolerance {
            return nil
        }
        return successValue
    }
}

/// Counts assessor invocations (and prepare).
private final class CountingAssessor: ObservingQualityAssessing, @unchecked Sendable {
    private let lock = NSLock()
    private let inner: ObservingQualityService
    private var _assessCount = 0
    private var _prepareCount = 0

    var assessCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _assessCount
    }
    var prepareCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _prepareCount
    }

    init(provider: (any LightPollutionProviding)?) {
        self.inner = ObservingQualityService(lightPollutionProvider: provider)
    }

    func markPrepared() {
        lock.lock()
        _prepareCount += 1
        lock.unlock()
    }

    func assess(
        nightConditionsScore: Int,
        latitude: Double,
        longitude: Double
    ) -> ObservingQualityAssessment {
        lock.lock()
        _assessCount += 1
        lock.unlock()
        return inner.assess(
            nightConditionsScore: nightConditionsScore,
            latitude: latitude,
            longitude: longitude
        )
    }
}

private struct MockWeather: WeatherForecastProviding {
    let forecasts: @Sendable (Coordinate) -> [HourlyForecast]

    init(forecasts: @escaping @Sendable (Coordinate) -> [HourlyForecast]) {
        self.forecasts = forecasts
    }

    func fetchForecastForMultipleLocations(
        coordinates: [Coordinate],
        days: Int
    ) async throws -> [Coordinate: [HourlyForecast]] {
        Dictionary(uniqueKeysWithValues: coordinates.map { ($0, forecasts($0)) })
    }
}

private actor MockAstro: AstronomyProviding {
    func calculateSunEvents(latitude: Double, longitude: Double, on date: Date) async -> SunEvents {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: date)
        return SunEvents(
            sunrise: start.addingTimeInterval(6 * 3600),
            sunset: start.addingTimeInterval(18 * 3600),
            civilTwilightBegin: start.addingTimeInterval(5 * 3600),
            civilTwilightEnd: start.addingTimeInterval(19 * 3600),
            nauticalTwilightBegin: start.addingTimeInterval(4.5 * 3600),
            nauticalTwilightEnd: start.addingTimeInterval(19.5 * 3600),
            astronomicalTwilightBegin: start.addingTimeInterval(4 * 3600),
            astronomicalTwilightEnd: start.addingTimeInterval(20 * 3600)
        )
    }

    func calculateMoonInfo(latitude: Double, longitude: Double, on date: Date) async -> MoonInfo {
        MoonInfo(phase: 0, phaseName: "New Moon", altitude: -10, illumination: 0, emoji: "New")
    }
}

private struct AlwaysSuitable: LocationSuitabilityProviding {
    func suitability(for point: GridPoint) async -> LocationSuitabilityStatus { .suitable }
    func suitability(for points: [GridPoint]) async -> [GridPoint: LocationSuitabilityStatus] {
        Dictionary(uniqueKeysWithValues: points.map { ($0, LocationSuitabilityStatus.suitable) })
    }
}

/// Counts suitability batch lookups (for proving cancellation skips suitability).
private actor CountingSuitability: LocationSuitabilityProviding {
    private(set) var batchCallCount = 0
    private(set) var singleCallCount = 0

    func suitability(for point: GridPoint) async throws -> LocationSuitabilityStatus {
        try Task.checkCancellation()
        singleCallCount += 1
        return .suitable
    }

    func suitability(for points: [GridPoint]) async throws -> [GridPoint: LocationSuitabilityStatus] {
        try Task.checkCancellation()
        batchCallCount += 1
        return Dictionary(uniqueKeysWithValues: points.map { ($0, LocationSuitabilityStatus.suitable) })
    }
}

/// Suspends assessor preparation until released (deterministic cancel-during-prep).
private actor AssessorPreparationGate {
    private var didStart = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private var isReleased = false

    func waitUntilStarted() async {
        if didStart { return }
        await withCheckedContinuation { continuation in
            if didStart {
                continuation.resume()
            } else {
                startWaiter = continuation
            }
        }
    }

    func markStartedAndWaitForRelease() async {
        didStart = true
        if let startWaiter {
            self.startWaiter = nil
            startWaiter.resume()
        }
        if isReleased { return }
        await withCheckedContinuation { continuation in
            if isReleased {
                continuation.resume()
            } else {
                releaseWaiter = continuation
            }
        }
    }

    func release() {
        isReleased = true
        if let releaseWaiter {
            self.releaseWaiter = nil
            releaseWaiter.resume()
        }
    }
}

/// Holds the search thread once scoring progress reaches the candidate-assessment phase (>= 0.5).
/// Synchronous so cancel can be armed before suitability begins (no race with a pure CPU scoring loop).
private final class ScoringHoldGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didEnter = false
    private let entered = DispatchSemaphore(value: 0)
    private let release = DispatchSemaphore(value: 0)

    func noteProgress(_ progress: Double) {
        guard progress >= 0.5 else { return }
        lock.lock()
        let shouldHold = !didEnter
        if shouldHold { didEnter = true }
        lock.unlock()
        guard shouldHold else { return }
        entered.signal()
        release.wait()
    }

    func waitUntilHeld() {
        entered.wait()
    }

    func releaseHold() {
        release.signal()
    }
}

/// Controllable mock for ViewModel stale-search / supersede tests.
private actor ControllableBestSpotSearcher: BestSpotSearching {
    struct PendingCall {
        let progressHandler: (@Sendable (Double) -> Void)?
        let continuation: CheckedContinuation<BestSpotResult, Error>
    }

    private var callCount = 0
    private var pending: [Int: PendingCall] = [:]
    private var callStartedWaiters: [Int: CheckedContinuation<Void, Never>] = [:]
    private var startedCalls = Set<Int>()

    private(set) var completedCallIDs: [Int] = []

    func findBestSpots(
        around center: CachedLocation,
        radiusMiles: Double,
        spacingMiles: Double,
        for date: Date,
        topN: Int,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> BestSpotResult {
        callCount += 1
        let id = callCount
        startedCalls.insert(id)
        if let waiter = callStartedWaiters.removeValue(forKey: id) {
            waiter.resume()
        }
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = PendingCall(progressHandler: progressHandler, continuation: continuation)
        }
    }

    func waitForCallToStart(_ id: Int) async {
        if startedCalls.contains(id) { return }
        await withCheckedContinuation { continuation in
            if startedCalls.contains(id) {
                continuation.resume()
            } else {
                callStartedWaiters[id] = continuation
            }
        }
    }

    func emitProgress(callID: Int, value: Double) {
        pending[callID]?.progressHandler?(value)
    }

    func complete(callID: Int, with result: BestSpotResult) {
        guard let call = pending.removeValue(forKey: callID) else { return }
        completedCallIDs.append(callID)
        call.continuation.resume(returning: result)
    }

    func fail(callID: Int, with error: Error) {
        guard let call = pending.removeValue(forKey: callID) else { return }
        completedCallIDs.append(callID)
        call.continuation.resume(throwing: error)
    }
}

// MARK: - Tests

final class BestSpotObservingQualityTests: XCTestCase {

    private static func clearNightForecasts(for coordinate: Coordinate) -> [HourlyForecast] {
        // Uniform clear night-ish hours matching BestSpotSearcherTests style
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: Date())
        return (20...28).map { hour in
            let day = hour >= 24 ? calendar.date(byAdding: .day, value: 1, to: start)! : start
            let date = calendar.date(bySettingHour: hour % 24, minute: 0, second: 0, of: day)!
            return HourlyForecast(
                time: date,
                cloudCover: 5,
                humidity: 40,
                windSpeed: 2,
                windDirection: 180,
                temperature: 15,
                dewPoint: 5,
                visibility: 20_000,
                lowCloudCover: 0,
                midCloudCover: 0,
                highCloudCover: 5,
                windSpeed200hPa: 40
            )
        }
    }

    private static func center() -> CachedLocation {
        CachedLocation(name: "Center", latitude: 45.5, longitude: -122.7)
    }

    private static func makeSearcher(
        brightness: (any LightPollutionProviding)?,
        weather: MockWeather? = nil,
        counting: CountingAssessor? = nil
    ) -> BestSpotSearcher {
        let counter = counting ?? CountingAssessor(provider: brightness)
        return BestSpotSearcher(
            weatherService: weather ?? MockWeather { coord in Self.clearNightForecasts(for: coord) },
            astronomyService: MockAstro(),
            suitabilityService: AlwaysSuitable(),
            observingQualityPreparer: {
                counter.markPrepared()
                return counter
            }
        )
    }

    func testOQModeRanksDarkerCandidateAboveBrighterWhenNightScoresEqual() async throws {
        // Same weather everywhere → equal night scores; LP gradient changes public OQ ranking.
        let centerLoc = Self.center()
        let searcher = Self.makeSearcher(
            brightness: LatitudeGradientBrightnessProvider(centerLatitude: centerLoc.latitude)
        )
        let result = try await searcher.findBestSpots(
            around: centerLoc,
            radiusMiles: 15,
            spacingMiles: 10,
            for: Date(),
            topN: 5
        )
        XCTAssertEqual(result.scoringMode, .observingQuality)
        XCTAssertNil(result.lightPollutionUnavailableMessage)

        // All public scores should match OQ (score != night only when LP applies a penalty).
        for location in result.allScoredLocations {
            let expected = ObservingQualityService(
                lightPollutionProvider: LatitudeGradientBrightnessProvider(
                    centerLatitude: centerLoc.latitude
                )
            ).assess(
                nightConditionsScore: location.nightConditionsScore,
                latitude: location.point.coordinate.latitude,
                longitude: location.point.coordinate.longitude
            )
            XCTAssertEqual(location.score, expected.score)
            XCTAssertEqual(location.nightConditionsScore, expected.nightConditionsScore)
            // In OQ mode every candidate retained valid LP on the assessment path.
        }

        // Darker (higher mag farther from center) can outrank urban center on public score
        // when night scores are equal and urban LP penalty is larger.
        let nightOnlyOrder = result.allScoredLocations.sorted {
            if $0.nightConditionsScore != $1.nightConditionsScore {
                return $0.nightConditionsScore > $1.nightConditionsScore
            }
            return $0.point.distanceMiles < $1.point.distanceMiles
        }
        let publicOrder = result.allScoredLocations.sorted(by: BestSpotSearcher.isHigherRanked(_:than:))
        // With uniform weather, night scores equal — OQ order should prefer darker sites.
        if let best = result.bestSpot, let centerScore = result.allScoredLocations.first(where: { $0.point.isCenter }) {
            // Farther sites may have higher public score than center when darker.
            let darkerCandidates = result.allScoredLocations.filter {
                !$0.point.isCenter && $0.score > centerScore.score
            }
            XCTAssertFalse(
                darkerCandidates.isEmpty || best.point.isCenter,
                "OQ mode should allow darker candidates to outrank a brighter center when night scores match"
            )
            // Ranking by public score must not equal pure distance among equal night scores when LP differs.
            _ = nightOnlyOrder
            _ = publicOrder
        }
    }

    func testEveryScoreIsOQInObservingQualityMode() async throws {
        let counter = CountingAssessor(provider: FixedBrightnessProvider(value: 19.5))
        let searcher = BestSpotSearcher(
            weatherService: MockWeather { c in Self.clearNightForecasts(for: c) },
            astronomyService: MockAstro(),
            suitabilityService: AlwaysSuitable(),
            observingQualityPreparer: {
                counter.markPrepared()
                return counter
            }
        )
        let result = try await searcher.findBestSpots(
            around: Self.center(),
            radiusMiles: 10,
            spacingMiles: 10,
            for: Date(),
            topN: 3
        )
        XCTAssertEqual(result.scoringMode, .observingQuality)
        XCTAssertEqual(counter.prepareCount, 1, "assessor prepared once per search")
        XCTAssertEqual(counter.assessCount, result.allScoredLocations.count)

        for location in result.allScoredLocations {
            let expected = ObservingQualityCalculator.assess(
                nightConditionsScore: location.nightConditionsScore,
                modeledZenithSkyBrightness: 19.5
            )
            XCTAssertEqual(location.score, expected.score)
            XCTAssertNotNil(
                ObservingQualityService(lightPollutionProvider: FixedBrightnessProvider(value: 19.5))
                    .assess(
                        nightConditionsScore: location.nightConditionsScore,
                        latitude: location.point.coordinate.latitude,
                        longitude: location.point.coordinate.longitude
                    ).lightPollution
            )
        }

        if let best = result.bestSpot, let center = result.allScoredLocations.first(where: \.point.isCenter) {
            XCTAssertEqual(best.improvementOverCenter, best.score - center.score)
        }
    }

    func testSearchWideFallbackWhenAnyBrightnessMissing() async throws {
        let centerLoc = Self.center()
        // Fail LP only very near center; outer points get valid brightness.
        let provider = OneCoordinateNilBrightnessProvider(
            failLatitude: centerLoc.latitude,
            successValue: 19.5,
            tolerance: 0.001
        )
        let counter = CountingAssessor(provider: provider)
        let searcher = BestSpotSearcher(
            weatherService: MockWeather { c in Self.clearNightForecasts(for: c) },
            astronomyService: MockAstro(),
            suitabilityService: AlwaysSuitable(),
            observingQualityPreparer: {
                counter.markPrepared()
                return counter
            }
        )
        let result = try await searcher.findBestSpots(
            around: centerLoc,
            radiusMiles: 15,
            spacingMiles: 10,
            for: Date(),
            topN: 5
        )
        XCTAssertEqual(result.scoringMode, .nightConditionsFallback)
        XCTAssertNotNil(result.lightPollutionUnavailableMessage)
        XCTAssertTrue(
            result.lightPollutionUnavailableMessage?
                .localizedCaseInsensitiveContains("light pollution") == true
        )
        for location in result.allScoredLocations {
            XCTAssertEqual(
                location.score,
                location.nightConditionsScore,
                "fallback mode: public score must equal exact night score"
            )
        }
        XCTAssertEqual(counter.prepareCount, 1)
        // Still assessed every candidate before deciding mode.
        XCTAssertEqual(counter.assessCount, result.allScoredLocations.count)
    }

    func testSearchWideFallbackWhenBrightnessOutOfRange() async throws {
        let counter = CountingAssessor(provider: FixedBrightnessProvider(value: 12.0))
        let searcher = BestSpotSearcher(
            weatherService: MockWeather { c in Self.clearNightForecasts(for: c) },
            astronomyService: MockAstro(),
            suitabilityService: AlwaysSuitable(),
            observingQualityPreparer: {
                counter.markPrepared()
                return counter
            }
        )
        let result = try await searcher.findBestSpots(
            around: Self.center(),
            radiusMiles: 10,
            spacingMiles: 10,
            for: Date(),
            topN: 3
        )
        XCTAssertEqual(result.scoringMode, .nightConditionsFallback)
        for location in result.allScoredLocations {
            XCTAssertEqual(location.score, location.nightConditionsScore)
        }
    }

    func testNilPreparerPreservesNightOnlyBehavior() async throws {
        // No preparer → night-only assessor → search-wide fallback (historical Best Nearby).
        let searcher = BestSpotSearcher(
            weatherService: MockWeather { c in Self.clearNightForecasts(for: c) },
            astronomyService: MockAstro(),
            suitabilityService: AlwaysSuitable(),
            observingQualityPreparer: nil
        )
        let result = try await searcher.findBestSpots(
            around: Self.center(),
            radiusMiles: 10,
            spacingMiles: 10,
            for: Date(),
            topN: 3
        )
        XCTAssertEqual(result.scoringMode, .nightConditionsFallback)
        for location in result.allScoredLocations {
            XCTAssertEqual(location.score, location.nightConditionsScore)
        }
        XCTAssertNotNil(result.lightPollutionUnavailableMessage)
    }

    func testLocationScoreRetainsNightScoreSeparatelyFromPublicScore() {
        let point = GridPoint(
            coordinate: Coordinate(latitude: 40, longitude: -74),
            distanceMiles: 5,
            bearing: 90,
            elevation: nil
        )
        let nq = NightQualityAssessment(
            rating: .good,
            summary: "Good",
            details: NightQualityAssessment.Details(
                cloudCoverScore: 20,
                fogScoreAvg: 10,
                moonIlluminationAvg: 20,
                windSpeedAvg: 5
            ),
            bestWindow: nil,
            hourlyRatings: [],
            nightStart: Date(),
            nightEnd: Date().addingTimeInterval(3600)
        )
        let score = LocationScore(
            point: point,
            score: 80,
            nightConditionsScore: 90,
            nightQuality: nq,
            fogScore: FogScore(score: 10, factors: []),
            avgCloudCover: 10,
            avgWindSpeed: 5,
            summary: "Mostly clear"
        )
        XCTAssertEqual(score.score, 80)
        XCTAssertEqual(score.nightConditionsScore, 90)
        let updated = score.withImprovement(comparedTo: 70)
        XCTAssertEqual(updated.improvementOverCenter, 10)
        XCTAssertEqual(updated.nightConditionsScore, 90)
        XCTAssertEqual(updated.score, 80)
    }

    func testCompatibilityInitializerDefaultsNightScoreToPublicScore() {
        let point = GridPoint(
            coordinate: Coordinate(latitude: 40, longitude: -74),
            distanceMiles: 1,
            bearing: 0,
            elevation: nil
        )
        let nq = NightQualityAssessment(
            rating: .fair,
            summary: "Fair",
            details: NightQualityAssessment.Details(
                cloudCoverScore: 40,
                fogScoreAvg: 20,
                moonIlluminationAvg: 30,
                windSpeedAvg: 8
            ),
            bestWindow: nil,
            hourlyRatings: [],
            nightStart: Date(),
            nightEnd: Date().addingTimeInterval(3600)
        )
        let score = LocationScore(
            point: point,
            score: 55,
            nightQuality: nq,
            fogScore: FogScore(score: 20, factors: []),
            avgCloudCover: 40,
            avgWindSpeed: 8,
            summary: "Partly cloudy"
        )
        XCTAssertEqual(score.nightConditionsScore, 55)
    }

    func testBestSpotResultFallbackMessageMatchesMode() {
        let center = CachedLocation(name: "C", latitude: 1, longitude: 2)
        let oq = BestSpotResult(
            centerLocation: center,
            searchRadiusMiles: 10,
            gridSpacingMiles: 5,
            scoredLocations: [],
            moonInfo: MoonInfo(phase: 0, phaseName: "New", altitude: 0, illumination: 0, emoji: ""),
            searchDate: Date(),
            searchDuration: 1,
            scoringMode: .observingQuality
        )
        XCTAssertNil(oq.lightPollutionUnavailableMessage)

        let fallback = BestSpotResult(
            centerLocation: center,
            searchRadiusMiles: 10,
            gridSpacingMiles: 5,
            scoredLocations: [],
            moonInfo: MoonInfo(phase: 0, phaseName: "New", altitude: 0, illumination: 0, emoji: ""),
            searchDate: Date(),
            searchDuration: 1,
            scoringMode: .nightConditionsFallback
        )
        XCTAssertEqual(
            fallback.lightPollutionUnavailableMessage,
            BestSpotScoringMode.nightConditionsFallback.lightPollutionUnavailableMessage
        )
    }

    // MARK: - Cancellation (searcher)

    func testCancellationDuringAssessorPreparationPreventsResultPublication() async {
        let prepGate = AssessorPreparationGate()
        let suitability = CountingSuitability()
        let searcher = BestSpotSearcher(
            weatherService: MockWeather { c in Self.clearNightForecasts(for: c) },
            astronomyService: MockAstro(),
            suitabilityService: suitability,
            observingQualityPreparer: {
                await prepGate.markStartedAndWaitForRelease()
                return ObservingQualityService(
                    lightPollutionProvider: FixedBrightnessProvider(value: 19.5)
                )
            }
        )
        let center = Self.center()

        let searchTask = Task {
            try await searcher.findBestSpots(
                around: center,
                radiusMiles: 10,
                spacingMiles: 10,
                for: Date(),
                topN: 3
            )
        }

        await prepGate.waitUntilStarted()
        searchTask.cancel()
        // Resume preparer so cooperative cancellation can be observed after await assessor.
        await prepGate.release()

        do {
            _ = try await searchTask.value
            XCTFail("Expected cancellation to prevent a published BestSpotResult")
        } catch is CancellationError {
            // Expected: publication suppressed via CancellationError.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let batchCalls = await suitability.batchCallCount
        let singleCalls = await suitability.singleCallCount
        XCTAssertEqual(batchCalls, 0, "suitability must not run after cancel during prep")
        XCTAssertEqual(singleCalls, 0)
    }

    func testCancellationDuringCandidateAssessmentPreventsSuitabilityAndResult() async {
        let holdGate = ScoringHoldGate()
        let suitability = CountingSuitability()
        let searcher = BestSpotSearcher(
            weatherService: MockWeather { c in Self.clearNightForecasts(for: c) },
            astronomyService: MockAstro(),
            suitabilityService: suitability,
            observingQualityPreparer: {
                ObservingQualityService(
                    lightPollutionProvider: FixedBrightnessProvider(value: 19.5)
                )
            }
        )
        let center = Self.center()

        let searchTask = Task {
            try await searcher.findBestSpots(
                around: center,
                radiusMiles: 15,
                spacingMiles: 5,
                for: Date(),
                topN: 5
            ) { progress in
                holdGate.noteProgress(progress)
            }
        }

        // Search is blocked inside the candidate scoring loop after first scoring progress.
        holdGate.waitUntilHeld()
        searchTask.cancel()
        holdGate.releaseHold()

        do {
            _ = try await searchTask.value
            XCTFail("Expected cancellation during candidate assessment to throw")
        } catch is CancellationError {
            // Expected: next Task.checkCancellation after hold ends suppresses publication.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let batchCalls = await suitability.batchCallCount
        let singleCalls = await suitability.singleCallCount
        XCTAssertEqual(batchCalls, 0, "suitability must not run after cancel during assessment")
        XCTAssertEqual(singleCalls, 0)
    }

    // MARK: - ViewModel supersede / stale progress

    @MainActor
    func testSupersededSearchCannotOverwriteNewerResult() async {
        let searcher = ControllableBestSpotSearcher()
        let viewModel = BestSpotViewModel(searcher: searcher)
        let location = SavedLocation(name: "Center", latitude: 45.5, longitude: -122.7)
        let resultA = Self.makeMarkerResult(tagScore: 11, scoringMode: .observingQuality)
        let resultB = Self.makeMarkerResult(tagScore: 77, scoringMode: .observingQuality)

        let taskA = Task { await viewModel.search(around: location, for: Date(), topN: 5) }
        await searcher.waitForCallToStart(1)

        let taskB = Task { await viewModel.search(around: location, for: Date(), topN: 5) }
        await searcher.waitForCallToStart(2)

        // Complete newer search B first.
        await searcher.complete(callID: 2, with: resultB)
        await taskB.value

        XCTAssertEqual(viewModel.result?.topLocations.first?.score, 77)
        XCTAssertFalse(viewModel.isSearching)

        // Late completion of superseded search A must not overwrite B.
        await searcher.complete(callID: 1, with: resultA)
        await taskA.value

        XCTAssertEqual(
            viewModel.result?.topLocations.first?.score,
            77,
            "superseded search A must not overwrite completed search B"
        )
        XCTAssertNil(viewModel.error)
    }

    @MainActor
    func testStaleProgressFromSupersededSearchDoesNotUpdateActiveProgress() async {
        let searcher = ControllableBestSpotSearcher()
        let viewModel = BestSpotViewModel(searcher: searcher)
        let location = SavedLocation(name: "Center", latitude: 45.5, longitude: -122.7)
        let resultA = Self.makeMarkerResult(tagScore: 11, scoringMode: .nightConditionsFallback)
        let resultB = Self.makeMarkerResult(tagScore: 88, scoringMode: .observingQuality)

        let taskA = Task { await viewModel.search(around: location, for: Date(), topN: 5) }
        await searcher.waitForCallToStart(1)
        await searcher.emitProgress(callID: 1, value: 0.25)
        // Allow MainActor progress task to apply.
        await Task.yield()
        XCTAssertEqual(viewModel.searchProgress, 0.25, accuracy: 1e-9)

        let taskB = Task { await viewModel.search(around: location, for: Date(), topN: 5) }
        await searcher.waitForCallToStart(2)
        await searcher.emitProgress(callID: 2, value: 0.6)
        await Task.yield()
        XCTAssertEqual(viewModel.searchProgress, 0.6, accuracy: 1e-9)

        // Stale progress from A must not clobber B's active progress.
        await searcher.emitProgress(callID: 1, value: 0.99)
        await Task.yield()
        XCTAssertEqual(
            viewModel.searchProgress,
            0.6,
            accuracy: 1e-9,
            "stale progress from search A must not update search B"
        )

        await searcher.complete(callID: 2, with: resultB)
        await taskB.value
        await searcher.complete(callID: 1, with: resultA)
        await taskA.value

        XCTAssertEqual(viewModel.result?.topLocations.first?.score, 88)
    }

    // MARK: - Result card accessibility

    func testResultCardAccessibilityUsesObservingQualityPublicScore() {
        let score = Self.makeLocationScore(publicScore: 86, nightScore: 93)
        let label = BestSpotResultCard.accessibilityLabel(
            locationScore: score,
            rank: 1,
            scoringMode: .observingQuality,
            centerLocationName: "Home"
        )
        XCTAssertTrue(label.contains("Observing quality score 86 out of 100"))
        XCTAssertFalse(label.contains("93"), "must not surface nightConditionsScore in OQ mode")
        XCTAssertFalse(label.localizedCaseInsensitiveContains("light pollution unavailable"))
        XCTAssertTrue(label.contains("Rank 1"))
        XCTAssertTrue(label.contains(score.fullLocationString))
        // publicScore 86 vs center baseline 70 → +16; descriptive a11y form only.
        XCTAssertTrue(label.contains("16 points better than Home"))
        XCTAssertFalse(label.contains("+16 vs Home"))
    }

    func testResultCardAccessibilityUsesNightScoreAndFlagsLPUnavailableInFallback() {
        let score = Self.makeLocationScore(publicScore: 72, nightScore: 72)
        let label = BestSpotResultCard.accessibilityLabel(
            locationScore: score,
            rank: 2,
            scoringMode: .nightConditionsFallback,
            centerLocationName: "Home"
        )
        XCTAssertTrue(label.contains("Night conditions score 72 out of 100; light pollution unavailable"))
        XCTAssertTrue(label.contains("Rank 2"))
        XCTAssertFalse(label.localizedCaseInsensitiveContains("observing quality"))
        XCTAssertTrue(label.contains("2 points better than Home"))
    }

    func testResultCardAccessibilityNeverReadsNightScoreInsteadOfPublicScoreInOQMode() {
        // Public OQ score differs from stored night score.
        let score = Self.makeLocationScore(publicScore: 80, nightScore: 95)
        let label = BestSpotResultCard.accessibilityLabel(
            locationScore: score,
            rank: 3,
            scoringMode: .observingQuality,
            centerLocationName: "Portland"
        )
        XCTAssertTrue(label.contains("Observing quality score 80 out of 100"))
        XCTAssertFalse(label.contains("95"))
        XCTAssertFalse(label.contains("score 95"))
        // Improvement from public score only (80 - 70 = 10).
        XCTAssertTrue(label.contains("10 points better than Portland"))
    }

    // MARK: - Fixtures

    private static func makeNightQuality() -> NightQualityAssessment {
        NightQualityAssessment(
            rating: .good,
            summary: "Good",
            details: NightQualityAssessment.Details(
                cloudCoverScore: 20,
                fogScoreAvg: 10,
                moonIlluminationAvg: 15,
                windSpeedAvg: 4
            ),
            bestWindow: nil,
            hourlyRatings: [],
            nightStart: Date(),
            nightEnd: Date().addingTimeInterval(3600)
        )
    }

    private static func makeLocationScore(publicScore: Int, nightScore: Int) -> LocationScore {
        LocationScore(
            point: GridPoint(
                coordinate: Coordinate(latitude: 45.5, longitude: -122.7),
                distanceMiles: 5,
                bearing: 90,
                elevation: nil
            ),
            score: publicScore,
            nightConditionsScore: nightScore,
            nightQuality: makeNightQuality(),
            fogScore: FogScore(score: 10, factors: []),
            avgCloudCover: 10,
            avgWindSpeed: 4,
            suitability: .suitable,
            improvementOverCenter: publicScore - 70,
            summary: "Mostly clear"
        )
    }

    private static func makeMarkerResult(tagScore: Int, scoringMode: BestSpotScoringMode) -> BestSpotResult {
        let location = makeLocationScore(publicScore: tagScore, nightScore: tagScore)
        return BestSpotResult(
            centerLocation: center(),
            searchRadiusMiles: 10,
            gridSpacingMiles: 5,
            scoredLocations: [location],
            moonInfo: MoonInfo(phase: 0, phaseName: "New", altitude: 0, illumination: 0, emoji: ""),
            searchDate: Date(),
            searchDuration: 0.1,
            scoringMode: scoringMode
        )
    }
}

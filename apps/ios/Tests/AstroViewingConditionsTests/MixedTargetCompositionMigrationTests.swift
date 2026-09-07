import AstroEngine
@testable import SharedCode
import XCTest

/// Migration equivalence for the mixed-target composition slice.
///
/// `LegacyCompositionOracle` is a verbatim copy of the pre-migration final
/// sort/truncate in `DefaultTargetRecommendationService.recommendations(for:limit:)`.
/// It deliberately calls **neither** `RecommendationComposition` nor
/// `TargetScoring.rankedIndices`, so a mistake in the extraction cannot make
/// both sides wrong together.
private enum LegacyCompositionOracle {
    static func compose(
        _ candidates: [TargetRecommendation],
        limit: Int
    ) -> [TargetRecommendation] {
        let scores = candidates.map(\.score)
        let bestTimes = candidates.map { $0.visibilityWindow.bestTime }
        return scores.indices.sorted {
            if scores[$0] != scores[$1] { return scores[$0] > scores[$1] }
            if bestTimes[$0] != bestTimes[$1] { return bestTimes[$0] < bestTimes[$1] }
            return $0 < $1
        }.prefix(max(0, limit)).map { candidates[$0] }
    }
}

final class MixedTargetCompositionMigrationTests: XCTestCase {

    // MARK: - Migration equivalence

    /// Every representative mixed set, at every limit the service can be asked
    /// for, must produce the pre-migration list — identical objects in identical
    /// order, not merely equal scores.
    func testServiceMatchesLegacyCompositionAcrossMixedSets() {
        var comparisons = 0
        var selectedRows = 0

        for (setIndex, plan) in Self.candidatePlans.enumerated() {
            for limit in Self.limits {
                let context = Self.context()
                let candidates = plan.expectedCandidates(context: context)
                let service = plan.service()

                let actual = service.recommendations(for: context, limit: limit)
                let legacy = LegacyCompositionOracle.compose(candidates, limit: limit)
                let label = "set \(setIndex) limit \(limit)"

                comparisons += 1
                selectedRows += actual.count
                XCTAssertEqual(actual.count, legacy.count, label)
                XCTAssertEqual(actual.map(\.id), legacy.map(\.id), label)
                XCTAssertEqual(actual.map(\.score), legacy.map(\.score), label)
                XCTAssertEqual(
                    actual.map { $0.visibilityWindow.bestTime },
                    legacy.map { $0.visibilityWindow.bestTime },
                    label
                )
                XCTAssertEqual(actual, legacy, label)
            }
        }

        XCTAssertEqual(comparisons, Self.candidatePlans.count * Self.limits.count)
        XCTAssertGreaterThan(selectedRows, 0)
    }

    // MARK: - Specialized results survive composition untouched

    func testSpecializedMoonAndPlanetResultsArePreservedExactly() {
        let context = Self.context()
        let plan = Self.mixedNight
        let candidates = plan.expectedCandidates(context: context)
        let composed = plan.service().recommendations(for: context, limit: 10)

        for key in ["moon", "jupiter"] {
            let original = try! XCTUnwrap(candidates.first { $0.target.id == key })
            let survivor = try! XCTUnwrap(composed.first { $0.target.id == key })
            XCTAssertEqual(survivor, original)
            XCTAssertEqual(survivor.score, original.score)
            XCTAssertEqual(survivor.reasons, original.reasons)
            XCTAssertEqual(survivor.summary, original.summary)
            XCTAssertEqual(survivor.visibilityWindow, original.visibilityWindow)
        }
    }

    /// The specialized Moon and planet scores here are deliberately far from
    /// what the generic scorer would produce for the same windows. Routing
    /// either back through `DefaultTargetRecommendationScorer` changes the
    /// order, so a re-score regression is observable at production level.
    func testGenericRescoringOfTheMoonOrPlanetsWouldChangeTheOrder() {
        let context = Self.context()
        let plan = Self.mixedNight

        let composed = plan.service().recommendations(for: context, limit: 10)
        XCTAssertEqual(composed.map(\.target.id), ["moon", "jupiter", "m31", "m13", "venus"])

        let generic = DefaultTargetRecommendationScorer()
        let rescored = plan.expectedCandidates(context: context).map { candidate -> Int in
            generic.recommendation(
                for: candidate.target,
                window: candidate.visibilityWindow,
                context: context
            ).score
        }
        let specialized = plan.expectedCandidates(context: context).map(\.score)
        XCTAssertNotEqual(rescored, specialized)

        let moonIndex = plan.expectedCandidates(context: context)
            .firstIndex { $0.target.id == "moon" }!
        let venusIndex = plan.expectedCandidates(context: context)
            .firstIndex { $0.target.id == "venus" }!
        XCTAssertGreaterThan(specialized[moonIndex], rescored[moonIndex],
                             "the Moon's specialized score must not be reachable generically")
        XCTAssertLessThan(specialized[venusIndex], rescored[venusIndex],
                          "Venus's specialized score must not be reachable generically")
    }

    // MARK: - Provider-failure fall-through

    func testMissingSpecializedResultsFallThroughToTheGenericPathAsBefore() {
        let context = Self.context()
        let plan = Self.missingSpecializedResults
        let candidates = plan.expectedCandidates(context: context)
        let composed = plan.service().recommendations(for: context, limit: 10)

        // A nil specialized provider does not remove the target: production
        // falls through to the position provider plus the generic scorer, so
        // the Moon and the planet still contribute one generically scored row.
        XCTAssertEqual(Set(candidates.map(\.target.id)), ["m31", "moon", "venus"])
        XCTAssertEqual(composed, LegacyCompositionOracle.compose(candidates, limit: 10))
        for id in ["moon", "venus"] {
            let row = try! XCTUnwrap(composed.first { $0.target.id == id })
            // The injected generic scorer produced this row, not a specialized
            // provider: the summary and score are the generic path's.
            XCTAssertEqual(row.summary, "Generic \(id)")
            XCTAssertEqual(row.reasons, [.goodNightQuality])
            XCTAssertNotEqual(row.summary, "Specialized \(id)")
        }
        XCTAssertEqual(composed.map(\.target.id), ["m31", "venus", "moon"])
    }

    func testATargetWithNoVisibilityWindowsContributesNothing() {
        let context = Self.context()
        let composed = Self.emptyWindows.service().recommendations(for: context, limit: 10)
        XCTAssertTrue(composed.isEmpty)
    }

    // MARK: - Ordering, ties, limits

    func testMultipleWindowsForOneTargetProduceMultipleRankedRows() {
        let context = Self.context()
        let plan = Self.multipleWindows
        let composed = plan.service().recommendations(for: context, limit: 10)

        XCTAssertEqual(composed.count, 3)
        XCTAssertEqual(composed.filter { $0.target.id == "m31" }.count, 2)
        XCTAssertEqual(composed, LegacyCompositionOracle.compose(
            plan.expectedCandidates(context: context), limit: 10))
        XCTAssertEqual(Set(composed.map(\.id)).count, 3, "duplicate target ids stay distinguishable")
    }

    func testCompleteTiesPreserveCatalogOrder() {
        let context = Self.context()
        let plan = Self.completeTie
        let composed = plan.service().recommendations(for: context, limit: 10)

        XCTAssertEqual(composed.map(\.target.id), ["venus", "m45", "moon"])
        XCTAssertEqual(composed, LegacyCompositionOracle.compose(
            plan.expectedCandidates(context: context), limit: 10))
    }

    func testEqualScoresBreakOnTheEarlierBestTime() {
        let context = Self.context()
        let plan = Self.equalScoresDifferentBestTimes
        let composed = plan.service().recommendations(for: context, limit: 10)

        XCTAssertEqual(composed.map(\.target.id), ["m42", "moon", "saturn"])
    }

    func testZeroNegativeAndOversizedLimits() {
        let context = Self.context()
        let plan = Self.mixedNight

        XCTAssertTrue(plan.service().recommendations(for: context, limit: 0).isEmpty)
        XCTAssertTrue(plan.service().recommendations(for: context, limit: -1).isEmpty)
        XCTAssertTrue(plan.service().recommendations(for: context, limit: Int.min).isEmpty)
        XCTAssertEqual(plan.service().recommendations(for: context, limit: 500).count, 5)
        XCTAssertEqual(
            plan.service().recommendations(for: context, limit: 500),
            LegacyCompositionOracle.compose(plan.expectedCandidates(context: context), limit: 500)
        )
    }

    func testEmptyCatalogComposesToNothingAtEveryLimit() {
        let context = Self.context()
        for limit in Self.limits {
            XCTAssertTrue(Self.emptyCatalog.service().recommendations(for: context, limit: limit).isEmpty)
        }
    }

    // MARK: - Plans

    /// One deterministic mixed night: what the catalog holds, which specialized
    /// results exist, and which generic windows the position provider returns.
    fileprivate struct Plan {
        let entries: [Entry]

        struct Entry {
            let target: ObservableTarget
            /// A specialized Moon/planet result, or `nil` to make the
            /// specialized provider fall through as production does.
            let specialized: (score: Int, bestHour: Int)?
            /// Generic windows for the deep-sky path and for the fall-through.
            let windows: [(startHour: Int, bestHour: Int, score: Int)]
        }

        func service() -> DefaultTargetRecommendationService {
            DefaultTargetRecommendationService(
                catalogProvider: PlanCatalogProvider(targets: entries.map(\.target)),
                positionProvider: PlanPositionProvider(plan: self),
                scorer: PlanScorer(plan: self),
                moonRecommendationProvider: PlanSpecializedProvider(plan: self, type: .moon),
                planetRecommendationProvider: PlanSpecializedProvider(plan: self, type: .planet)
            )
        }

        /// The candidate array the service builds, in the same order, rebuilt
        /// here independently of the composition under test.
        func expectedCandidates(context: TargetRecommendationContext) -> [TargetRecommendation] {
            entries.flatMap { entry -> [TargetRecommendation] in
                if entry.target.type == .moon || entry.target.type == .planet,
                   let specialized = entry.specialized {
                    return [MixedTargetCompositionMigrationTests.specializedRecommendation(
                        target: entry.target, score: specialized.score, bestHour: specialized.bestHour)]
                }
                return entry.windows.map { window in
                    MixedTargetCompositionMigrationTests.genericRecommendation(
                        target: entry.target, window: window, context: context)
                }
            }
        }

        func entry(for target: ObservableTarget) -> Entry? {
            entries.first { $0.target.id == target.id }
        }
    }

    fileprivate static func window(startHour: Int, bestHour: Int) -> TargetVisibilityWindow {
        TargetVisibilityWindow(
            start: date(hour: startHour),
            end: date(hour: startHour + 2),
            bestTime: date(hour: bestHour),
            maxAltitude: 50,
            direction: "S"
        )
    }

    /// Mirrors the specialized providers: one recommendation, its own score, its
    /// own reason set and its own copy — never the generic scorer's.
    fileprivate static func specializedRecommendation(
        target: ObservableTarget, score: Int, bestHour: Int
    ) -> TargetRecommendation {
        TargetRecommendation(
            target: target,
            score: score,
            visibilityWindow: window(startHour: bestHour - 1, bestHour: bestHour),
            reasons: target.type == .moon ? [.moonInterference] : [.planetMoonlightResistant],
            summary: "Specialized \(target.id)"
        )
    }

    fileprivate static func genericRecommendation(
        target: ObservableTarget,
        window plan: (startHour: Int, bestHour: Int, score: Int),
        context: TargetRecommendationContext
    ) -> TargetRecommendation {
        TargetRecommendation(
            target: target,
            score: plan.score,
            visibilityWindow: window(startHour: plan.startHour, bestHour: plan.bestHour),
            reasons: [.goodNightQuality],
            summary: "Generic \(target.id)"
        )
    }

    // MARK: - Representative mixed sets

    fileprivate static let mixedNight = Plan(entries: [
        Plan.Entry(target: target("m31", .deepSky), specialized: nil,
                   windows: [(21, 22, 62)]),
        Plan.Entry(target: target("moon", .moon), specialized: (91, 23),
                   windows: [(22, 23, 40)]),
        Plan.Entry(target: target("jupiter", .planet), specialized: (73, 21),
                   windows: [(20, 21, 55)]),
        Plan.Entry(target: target("m13", .deepSky), specialized: nil,
                   windows: [(20, 21, 55)]),
        Plan.Entry(target: target("venus", .planet), specialized: (18, 19),
                   windows: [(18, 19, 44)]),
    ])

    private static let missingSpecializedResults = Plan(entries: [
        Plan.Entry(target: target("m31", .deepSky), specialized: nil, windows: [(21, 22, 62)]),
        Plan.Entry(target: target("moon", .moon), specialized: nil, windows: [(22, 23, 40)]),
        Plan.Entry(target: target("venus", .planet), specialized: nil, windows: [(18, 19, 44)]),
    ])

    private static let multipleWindows = Plan(entries: [
        Plan.Entry(target: target("m31", .deepSky), specialized: nil,
                   windows: [(20, 21, 58), (23, 24, 64)]),
        Plan.Entry(target: target("jupiter", .planet), specialized: (58, 21), windows: []),
    ])

    private static let completeTie = Plan(entries: [
        Plan.Entry(target: target("venus", .planet), specialized: (66, 22), windows: []),
        Plan.Entry(target: target("m45", .deepSky), specialized: nil, windows: [(21, 22, 66)]),
        Plan.Entry(target: target("moon", .moon), specialized: (66, 22), windows: []),
    ])

    private static let equalScoresDifferentBestTimes = Plan(entries: [
        Plan.Entry(target: target("saturn", .planet), specialized: (70, 25), windows: []),
        Plan.Entry(target: target("m42", .deepSky), specialized: nil, windows: [(20, 21, 70)]),
        Plan.Entry(target: target("moon", .moon), specialized: (70, 23), windows: []),
    ])

    private static let emptyWindows = Plan(entries: [
        Plan.Entry(target: target("m31", .deepSky), specialized: nil, windows: []),
        Plan.Entry(target: target("moon", .moon), specialized: nil, windows: []),
    ])

    private static let emptyCatalog = Plan(entries: [])

    fileprivate static let candidatePlans: [Plan] = [
        mixedNight, missingSpecializedResults, multipleWindows, completeTie,
        equalScoresDifferentBestTimes, emptyWindows, emptyCatalog,
    ]

    private static let limits = [-1, 0, 1, 2, 3, 5, 500]

    // MARK: - Fixtures

    private static func target(_ id: String, _ type: ObservableTargetType) -> ObservableTarget {
        ObservableTarget(
            id: id,
            name: id.uppercased(),
            type: type,
            preferredEquipment: .binoculars,
            difficulty: 0.3,
            deepSkyObjectType: type == .deepSky ? .galaxy : nil
        )
    }

    fileprivate static func date(hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 1 + hour / 24
        components.hour = hour % 24
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    fileprivate static func context() -> TargetRecommendationContext {
        TargetRecommendationContext(
            location: CachedLocation(name: "Test", latitude: 34, longitude: -118, elevation: 0),
            astronomicalNightStart: date(hour: 20),
            astronomicalNightEnd: date(hour: 29),
            nightQuality: NightQualityAssessment(
                rating: NightQualityAssessment.Rating.from(score: 0.2),
                summary: "Test conditions",
                details: NightQualityAssessment.Details(
                    cloudCoverScore: 5, fogScoreAvg: 5, moonIlluminationAvg: 40, windSpeedAvg: 2
                ),
                bestWindow: NightQualityAssessment.TimeWindow(
                    start: date(hour: 21), end: date(hour: 24)),
                hourlyRatings: (20..<29).map { hour in
                    NightQualityAssessment.HourlyRating(
                        time: date(hour: hour), score: 0.2, cloudCover: 5, fogScore: 5,
                        moonIllumination: 40, moonAltitude: 20, windSpeed: 2)
                },
                nightStart: date(hour: 20),
                nightEnd: date(hour: 29)
            ),
            moonInfo: MoonInfo(
                phase: 0.4, phaseName: "Test Moon", altitude: 20, illumination: 40, emoji: "")
        )
    }
}

// MARK: - Plan-backed doubles

private struct PlanCatalogProvider: TargetCatalogProvider {
    let targets: [ObservableTarget]

    func targets(for context: TargetRecommendationContext) -> [ObservableTarget] { targets }
}

private struct PlanPositionProvider: TargetPositionProvider {
    let plan: MixedTargetCompositionMigrationTests.Plan

    func visibilityWindows(
        for target: ObservableTarget,
        context: TargetRecommendationContext
    ) -> [TargetVisibilityWindow] {
        (plan.entry(for: target)?.windows ?? []).map {
            MixedTargetCompositionMigrationTests.window(startHour: $0.startHour, bestHour: $0.bestHour)
        }
    }
}

private struct PlanScorer: TargetRecommendationScoring {
    let plan: MixedTargetCompositionMigrationTests.Plan

    func recommendation(
        for target: ObservableTarget,
        window: TargetVisibilityWindow,
        context: TargetRecommendationContext
    ) -> TargetRecommendation {
        let match = plan.entry(for: target)?.windows.first { candidate in
            MixedTargetCompositionMigrationTests
                .window(startHour: candidate.startHour, bestHour: candidate.bestHour) == window
        }
        return MixedTargetCompositionMigrationTests.genericRecommendation(
            target: target, window: match ?? (0, 0, 0), context: context)
    }
}

private struct PlanSpecializedProvider: MoonTargetRecommendationProviding,
                                        PlanetTargetRecommendationProviding {
    let plan: MixedTargetCompositionMigrationTests.Plan
    let type: ObservableTargetType

    func recommendation(
        for target: ObservableTarget,
        context: TargetRecommendationContext
    ) -> TargetRecommendation? {
        guard target.type == type, let specialized = plan.entry(for: target)?.specialized else {
            return nil
        }
        return MixedTargetCompositionMigrationTests.specializedRecommendation(
            target: target, score: specialized.score, bestHour: specialized.bestHour)
    }
}

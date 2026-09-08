import XCTest
@testable import AstroEngine

/// Migration equivalence for the deterministic Best Nearby composition slice.
///
/// The expected side below is a test-only transcription of the pre-migration
/// `BestSpotSearcher` decisions. Its legacy functions deliberately do not call
/// either migrated authority, either transport contract, or a production
/// wrapper around them.
final class LocationCompositionMigrationTests: XCTestCase {
    // MARK: - Frozen pre-migration score-set implementation

    private struct LegacyDraft {
        let isCenter: Bool
        let hasNighttimeRows: Bool
        let hasValidLightPollution: Bool
        let nightConditionsScore: Int
        let observingQualityScore: Int
    }

    private enum LegacyScoringMode: Equatable {
        case observingQuality
        case nightConditionsFallback
    }

    private struct LegacyRow: Equatable {
        let inputIndex: Int
        let publicScore: Int
        let improvementOverCenter: Int?
    }

    private struct LegacyResult: Equatable {
        let scoringMode: LegacyScoringMode
        let rows: [LegacyRow]
    }

    private enum LegacyOutcome: Equatable {
        case noScorableLocations
        case success(LegacyResult)
    }

    /// Frozen copy of the old `scoreLocationDraft` omission,
    /// `resolveScoringMode`, `makeLocationScore`, center lookup, and
    /// `withImprovement` chain.
    private static func legacyCompose(_ drafts: [LegacyDraft]) -> LegacyOutcome {
        let surviving = drafts.enumerated().filter { $0.element.hasNighttimeRows }
        guard !surviving.isEmpty else { return .noScorableLocations }

        let mode: LegacyScoringMode = surviving.allSatisfy {
            $0.element.hasValidLightPollution
        } ? .observingQuality : .nightConditionsFallback

        func publicScore(_ draft: LegacyDraft) -> Int {
            switch mode {
            case .observingQuality:
                return draft.observingQualityScore
            case .nightConditionsFallback:
                return draft.nightConditionsScore
            }
        }

        let centerScore = surviving.first { $0.element.isCenter }
            .map { publicScore($0.element) }
        return .success(LegacyResult(
            scoringMode: mode,
            rows: surviving.map { index, draft in
                let score = publicScore(draft)
                return LegacyRow(
                    inputIndex: index,
                    publicScore: score,
                    improvementOverCenter: centerScore.map { score - $0 }
                )
            }
        ))
    }

    // MARK: - Frozen pre-migration recommendability implementation

    /// Frozen copy of the old `LocationSuitabilityStatus.isRecommendable`
    /// switch. It intentionally does not read that property.
    private static func legacyIsRecommendable(_ status: LocationSuitabilityStatus) -> Bool {
        switch status {
        case .suitable, .unknown:
            return true
        case .unchecked, .unsuitable:
            return false
        }
    }

    private static func legacyRecommendableIndices(
        _ statuses: [LocationSuitabilityStatus]
    ) -> [Int] {
        statuses.enumerated().compactMap { index, status in
            legacyIsRecommendable(status) ? index : nil
        }
    }

    // MARK: - New-authority adapters

    private func newOutcome(_ drafts: [LegacyDraft]) -> LegacyOutcome {
        do {
            let result = try LocationScoreComposition.compose(drafts.map { draft in
                LocationScoreCompositionCandidate(
                    isCenter: draft.isCenter,
                    nightConditionsScore: draft.nightConditionsScore,
                    hasNighttimeRows: draft.hasNighttimeRows,
                    observingQuality: ObservingQualityCompositionInput(
                        score: draft.observingQualityScore,
                        hasValidLightPollution: draft.hasValidLightPollution
                    )
                )
            })
            let mode: LegacyScoringMode = result.scoringMode == .observingQuality
                ? .observingQuality
                : .nightConditionsFallback
            return .success(LegacyResult(
                scoringMode: mode,
                rows: result.candidates.map {
                    LegacyRow(
                        inputIndex: $0.inputIndex,
                        publicScore: $0.publicScore,
                        improvementOverCenter: $0.improvementOverCenter
                    )
                }
            ))
        } catch LocationScoreCompositionError.noScorableLocations {
            return .noScorableLocations
        } catch {
            XCTFail("new authority rejected a production-valid oracle case: \(error)")
            return .noScorableLocations
        }
    }

    private func compare(_ drafts: [LegacyDraft], label: @autoclosure () -> String) {
        let expected = Self.legacyCompose(drafts)
        let actual = newOutcome(drafts)
        if actual != expected {
            XCTFail("Best Nearby composition diverged for \(label()): \(actual) vs \(expected)")
        }
    }

    // MARK: - Deterministic sweeps

    /// Exhaustive over 0...4 ordered drafts from 12 archetypes (nighttime row,
    /// LP participation, and three score-pair shapes), with the center absent
    /// or placed at every input index: 111,049 production-valid cases.
    func testExhaustiveStructureOrderingAndCenterPlacementMatchLegacy() {
        let scorePairs = [(0, 100), (50, 50), (100, 0)]
        let alphabet = [false, true].flatMap { hasRows in
            [false, true].flatMap { hasLP in
                scorePairs.map { night, oq in
                    LegacyDraft(
                        isCenter: false,
                        hasNighttimeRows: hasRows,
                        hasValidLightPollution: hasLP,
                        nightConditionsScore: night,
                        observingQualityScore: oq
                    )
                }
            }
        }

        var comparisons = 0
        var sawNoScorable = false
        var sawObservingQuality = false
        var sawFallback = false
        var sawMissingLPOnlyOnUnscorableRows = false
        var sawScorableMissingLPForceFallback = false
        var sawAllLPMissing = false
        var sawNoScorableCenter = false
        var sawCenterBeforeAndAfterSurvivors = false
        var deltaSigns = Set<Int>()

        for count in 0...4 {
            let sequenceCount = Self.power(alphabet.count, count)
            for encoded in 0..<sequenceCount {
                var remaining = encoded
                var base: [LegacyDraft] = []
                base.reserveCapacity(count)
                for _ in 0..<count {
                    base.append(alphabet[remaining % alphabet.count])
                    remaining /= alphabet.count
                }

                let centerPlacements: [Int?] = [nil] + Array(0..<count).map(Optional.some)
                for centerIndex in centerPlacements {
                    let drafts = base.enumerated().map { index, draft in
                        LegacyDraft(
                            isCenter: centerIndex == index,
                            hasNighttimeRows: draft.hasNighttimeRows,
                            hasValidLightPollution: draft.hasValidLightPollution,
                            nightConditionsScore: draft.nightConditionsScore,
                            observingQualityScore: draft.observingQualityScore
                        )
                    }
                    compare(drafts, label: "structure n=\(count) encoded=\(encoded) center=\(String(describing: centerIndex))")
                    comparisons += 1

                    let surviving = drafts.enumerated().filter { $0.element.hasNighttimeRows }
                    switch Self.legacyCompose(drafts) {
                    case .noScorableLocations:
                        sawNoScorable = true
                    case .success(let result):
                        sawObservingQuality = sawObservingQuality || result.scoringMode == .observingQuality
                        sawFallback = sawFallback || result.scoringMode == .nightConditionsFallback
                        sawNoScorableCenter = sawNoScorableCenter ||
                            result.rows.allSatisfy { $0.improvementOverCenter == nil }
                        for row in result.rows {
                            if let delta = row.improvementOverCenter {
                                deltaSigns.insert(delta.signum())
                            }
                        }
                    }

                    let scorableHasMissingLP = surviving.contains {
                        !$0.element.hasValidLightPollution
                    }
                    let unscorableHasMissingLP = drafts.contains {
                        !$0.hasNighttimeRows && !$0.hasValidLightPollution
                    }
                    if !surviving.isEmpty && scorableHasMissingLP {
                        sawScorableMissingLPForceFallback = true
                    }
                    if !surviving.isEmpty && !scorableHasMissingLP && unscorableHasMissingLP {
                        sawMissingLPOnlyOnUnscorableRows = true
                    }
                    if !surviving.isEmpty && drafts.allSatisfy({ !$0.hasValidLightPollution }) {
                        sawAllLPMissing = true
                    }
                    if let centerIndex,
                       drafts[centerIndex].hasNighttimeRows,
                       surviving.contains(where: { $0.offset < centerIndex }),
                       surviving.contains(where: { $0.offset > centerIndex }) {
                        sawCenterBeforeAndAfterSurvivors = true
                    }
                }
            }
        }

        XCTAssertEqual(comparisons, 111_049)
        XCTAssertTrue(sawNoScorable)
        XCTAssertTrue(sawObservingQuality)
        XCTAssertTrue(sawFallback)
        XCTAssertTrue(sawMissingLPOnlyOnUnscorableRows)
        XCTAssertTrue(sawScorableMissingLPForceFallback)
        XCTAssertTrue(sawAllLPMissing)
        XCTAssertTrue(sawNoScorableCenter)
        XCTAssertTrue(sawCenterBeforeAndAfterSurvivors)
        XCTAssertEqual(deltaSigns, Set([-1, 0, 1]))
    }

    /// Exhaustive two-row score matrix over every pair from
    /// {0, 1, 50, 99, 100}, all LP patterns, and absent/first/last center:
    /// 7,500 cases. Both coherent modes and every signed delta class occur.
    func testExhaustiveBoundaryScoreMatrixMatchesLegacy() {
        let scores = [0, 1, 50, 99, 100]
        var comparisons = 0
        var seenNightScores = Set<Int>()
        var seenOQScores = Set<Int>()
        var deltaSigns = Set<Int>()

        for firstNight in scores {
            for firstOQ in scores {
                for secondNight in scores {
                    for secondOQ in scores {
                        for lpPattern in 0..<4 {
                            for centerIndex: Int? in [nil, 0, 1] {
                                let drafts = [
                                    LegacyDraft(
                                        isCenter: centerIndex == 0,
                                        hasNighttimeRows: true,
                                        hasValidLightPollution: lpPattern & 1 != 0,
                                        nightConditionsScore: firstNight,
                                        observingQualityScore: firstOQ
                                    ),
                                    LegacyDraft(
                                        isCenter: centerIndex == 1,
                                        hasNighttimeRows: true,
                                        hasValidLightPollution: lpPattern & 2 != 0,
                                        nightConditionsScore: secondNight,
                                        observingQualityScore: secondOQ
                                    ),
                                ]
                                compare(
                                    drafts,
                                    label: "scores \(firstNight)/\(firstOQ), \(secondNight)/\(secondOQ), lp=\(lpPattern), center=\(String(describing: centerIndex))"
                                )
                                comparisons += 1
                                seenNightScores.formUnion([firstNight, secondNight])
                                seenOQScores.formUnion([firstOQ, secondOQ])
                                if case .success(let result) = Self.legacyCompose(drafts) {
                                    for row in result.rows {
                                        if let delta = row.improvementOverCenter {
                                            deltaSigns.insert(delta.signum())
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        XCTAssertEqual(comparisons, 7_500)
        XCTAssertEqual(seenNightScores, Set(scores))
        XCTAssertEqual(seenOQScores, Set(scores))
        XCTAssertEqual(deltaSigns, Set([-1, 0, 1]))
    }

    /// Exhaustive over every 0...5 row array drawn from the portable four-state
    /// suitability alphabet: 1,365 stable-filter comparisons.
    func testExhaustiveRecommendabilityArraysMatchLegacy() {
        let alphabet: [(LocationCompareSuitability, LocationSuitabilityStatus)] = [
            (.suitable, .suitable),
            (.unknown, .unknown(reason: .notChecked)),
            (.unchecked, .unchecked),
            (.unsuitable, .unsuitable(reason: "legacy test")),
        ]
        var comparisons = 0

        for count in 0...5 {
            for encoded in 0..<Self.power(alphabet.count, count) {
                var remaining = encoded
                var portable: [LocationCompareSuitability] = []
                var production: [LocationSuitabilityStatus] = []
                for _ in 0..<count {
                    let entry = alphabet[remaining % alphabet.count]
                    remaining /= alphabet.count
                    portable.append(entry.0)
                    production.append(entry.1)
                }

                let expected = Self.legacyRecommendableIndices(production)
                let actual = LocationRecommendabilityFilter
                    .recommendableInputIndices(for: portable)
                XCTAssertEqual(actual, expected, "recommendability n=\(count) encoded=\(encoded)")
                comparisons += 1
            }
        }

        XCTAssertEqual(comparisons, 1_365)
    }

    func testEveryProductionUnknownReasonRetainsLegacyEligibility() {
        let statuses: [LocationSuitabilityStatus] = [
            .unknown(reason: .notChecked),
            .unknown(reason: .geocodingFailed),
            .unknown(reason: .temporarilyUnavailable),
        ]
        let expected = Self.legacyRecommendableIndices(statuses)
        let actual = LocationRecommendabilityFilter.recommendableInputIndices(for: statuses)

        XCTAssertEqual(expected, [0, 1, 2])
        XCTAssertEqual(actual, expected)
    }

    private static func power(_ base: Int, _ exponent: Int) -> Int {
        (0..<exponent).reduce(1) { result, _ in result * base }
    }
}

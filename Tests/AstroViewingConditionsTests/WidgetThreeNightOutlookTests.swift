import Foundation
import SwiftUI
import XCTest
@testable import AstroViewingConditions
@testable import SharedCode

final class WidgetThreeNightOutlookTests: XCTestCase {
    private let timeZone = TimeZone(identifier: "America/Los_Angeles")!

    func testPayloadJSONRoundTrip() throws {
        let summary = makeSummary()
        let encoded = try JSONEncoder().encode(summary)
        XCTAssertEqual(
            try JSONDecoder().decode(
                WidgetThreeNightOutlookSummary.self,
                from: encoded
            ),
            summary
        )

        var legacyPayload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        legacyPayload.removeValue(forKey: "savedLocationID")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyPayload)
        XCTAssertNil(try JSONDecoder().decode(
            WidgetThreeNightOutlookSummary.self,
            from: legacyData
        ).savedLocationID)
    }

    func testSeparateCacheFilenameAtomicReplacementAndMissingCache() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertNil(AppGroupStorage.readWidgetThreeNightOutlookSummary(baseURL: directory))
        XCTAssertTrue(AppGroupStorage.writeWidgetThreeNightOutlookSummary(makeSummary(), baseURL: directory))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("widgetThreeNightOutlook.json").path
        ))
        let replacement = makeSummary(locationName: "Replacement")
        XCTAssertTrue(AppGroupStorage.writeWidgetThreeNightOutlookSummary(replacement, baseURL: directory))
        XCTAssertEqual(
            AppGroupStorage.readWidgetThreeNightOutlookSummary(baseURL: directory),
            replacement
        )
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("widgetTonightTargets.json").path
        ))
    }

    func testMaximumAgeMatchesConditionsCacheAndRejectsOlderSummary() {
        let generatedAt = date(day: 25, hour: 20)
        let summary = makeSummary(generatedAt: generatedAt)
        let maximumAge = WidgetThreeNightOutlookSummary.maximumAge

        XCTAssertEqual(maximumAge, SharedConditionsRepository.maximumAge)
        XCTAssertTrue(summary.isWithinMaximumAge(
            maximumAge,
            relativeTo: generatedAt.addingTimeInterval(maximumAge)
        ))
        XCTAssertFalse(summary.isWithinMaximumAge(
            maximumAge,
            relativeTo: generatedAt.addingTimeInterval(maximumAge + 1)
        ))
        XCTAssertFalse(summary.isWithinMaximumAge(
            maximumAge,
            relativeTo: generatedAt.addingTimeInterval(-1)
        ))
    }

    func testLocationMatchAndMismatch() {
        let summary = makeSummary()
        XCTAssertTrue(summary.locationMatches(latitude: 45.5, longitude: -122.7))
        XCTAssertFalse(summary.locationMatches(latitude: 47.6, longitude: -122.7))
    }

    func testSavedLocationIdentityRejectsNearbyDifferentSiteAndAcceptsSameSite() {
        let firstID = UUID()
        let summary = makeSummary(savedLocationID: firstID)

        XCTAssertFalse(summary.locationMatches(selectedLocation(
            id: UUID(), latitude: 45.500001, longitude: -122.699999, source: .saved
        )))
        XCTAssertTrue(summary.locationMatches(selectedLocation(
            id: firstID, latitude: 46.0, longitude: -123.0, source: .saved
        )))
        XCTAssertFalse(summary.locationMatches(selectedLocation(
            latitude: 45.5, longitude: -122.7, source: .currentGPS
        )))
        XCTAssertFalse(summary.locationMatches(CachedLocation(
            name: "Current Location", latitude: 45.5, longitude: -122.7
        )))
    }

    func testLegacySummaryUsesStrictCoordinateFallback() {
        let summary = makeSummary()
        XCTAssertTrue(summary.locationMatches(selectedLocation()))
        XCTAssertFalse(summary.locationMatches(selectedLocation(latitude: 45.50002)))
        XCTAssertFalse(summary.locationMatches(selectedLocation(id: UUID(), source: .saved)))
        XCTAssertFalse(summary.locationMatches(CachedLocation(
            id: UUID(), name: "Home", latitude: 45.5, longitude: -122.7
        )))
    }

    func testExactlyThreeOrderedEntriesRequired() {
        let summary = makeSummary()
        XCTAssertTrue(summary.hasCorrectlyOrderedNights())
        XCTAssertFalse(makeSummary(nights: Array(summary.nights.prefix(2))).hasCorrectlyOrderedNights())
        XCTAssertFalse(makeSummary(nights: summary.nights.reversed()).hasCorrectlyOrderedNights())
    }

    func testActiveNightValidationAcrossMidnight() {
        let summary = makeSummary()
        XCTAssertTrue(summary.matchesCurrentObservingNight(relativeTo: date(day: 25, hour: 14)))
        XCTAssertTrue(summary.matchesCurrentObservingNight(relativeTo: date(day: 26, hour: 1)))
        XCTAssertFalse(summary.matchesCurrentObservingNight(relativeTo: date(day: 26, hour: 5)))
    }

    func testProviderStateResolution() {
        let referenceDate = date(day: 25, hour: 21)
        let location = selectedLocation()
        let valid = makeSummary(generatedAt: referenceDate)

        XCTAssertEqual(resolve(valid, nil, at: referenceDate), .noLocation)
        XCTAssertEqual(resolve(nil, location, at: referenceDate), .noCache)
        XCTAssertEqual(
            resolve(
                makeSummary(
                    generatedAt: referenceDate.addingTimeInterval(
                        -WidgetThreeNightOutlookSummary.maximumAge - 1
                    )
                ),
                location, at: referenceDate
            ),
            .stale
        )
        XCTAssertEqual(
            resolve(makeSummary(generatedAt: referenceDate, latitude: 47.6), location, at: referenceDate),
            .locationMismatch
        )
        XCTAssertEqual(
            resolve(
                makeSummary(
                    generatedAt: referenceDate,
                    nights: shiftedNights(startDay: 24)
                ),
                location, at: referenceDate
            ),
            .observingNightMismatch
        )
        XCTAssertEqual(
            resolve(
                makeSummary(generatedAt: referenceDate, status: .unavailable),
                location, at: referenceDate
            ),
            .unavailable
        )
        XCTAssertEqual(
            resolve(
                makeSummary(generatedAt: referenceDate, nights: Array(valid.nights.prefix(2))),
                location, at: referenceDate
            ),
            .unavailable
        )
        XCTAssertEqual(
            resolve(
                makeSummary(generatedAt: referenceDate, nights: [
                    valid.nights[0], valid.nights[2], valid.nights[1]
                ]),
                location, at: referenceDate
            ),
            .unavailable
        )
        var missingScore = valid.nights
        missingScore[0] = night(
            label: "Tonight", day: 25, score: nil, status: .available, isBest: false
        )
        XCTAssertEqual(
            resolve(
                makeSummary(generatedAt: referenceDate, nights: missingScore),
                location, at: referenceDate
            ),
            .unavailable
        )
        XCTAssertEqual(resolve(valid, location, at: referenceDate), .available)
        XCTAssertEqual(
            resolve(
                makeSummary(generatedAt: referenceDate, savedLocationID: UUID()),
                location,
                at: referenceDate
            ),
            .locationMismatch
        )
        XCTAssertEqual(
            resolve(
                makeSummary(generatedAt: referenceDate),
                selectedLocation(id: UUID(), source: .saved),
                at: referenceDate
            ),
            .locationMismatch
        )
    }

    func testPublicationBeforeMidnightStartsWithCurrentObservingDate() {
        let referenceDate = date(day: 25, hour: 20)
        let savedLocationID = UUID()
        let decision = ThreeNightOutlookWidgetPayloadBuilder.publicationDecision(
            conditions: makeConditions(referenceDate: referenceDate, locationID: savedLocationID),
            existingSummary: nil, referenceDate: referenceDate, timeZone: timeZone
        )
        guard case let .publish(summary) = decision else {
            return XCTFail("Expected a published outlook")
        }
        XCTAssertEqual(summary.nights.map(\.observingDate), [date(day: 25), date(day: 26), date(day: 27)])
        XCTAssertEqual(summary.nights.map(\.displayLabel), ["Tonight", "Tomorrow", "Day After"])
        XCTAssertEqual(summary.savedLocationID, savedLocationID)
    }

    func testPublicationDuringReconstructableActiveNightKeepsPreviousDate() {
        let referenceDate = date(day: 26, hour: 1)
        let decision = ThreeNightOutlookWidgetPayloadBuilder.publicationDecision(
            conditions: makeConditions(referenceDate: referenceDate, dataStartDay: 25),
            existingSummary: nil, referenceDate: referenceDate, timeZone: timeZone
        )
        guard case let .publish(summary) = decision else {
            return XCTFail("Expected the reconstructable active night")
        }
        XCTAssertEqual(summary.nights.first?.observingDate, date(day: 25))
    }

    func testPublicationAfterActiveNightEndsUsesUpcomingCurrentDate() {
        let referenceDate = date(day: 26, hour: 4).addingTimeInterval(1)
        let decision = ThreeNightOutlookWidgetPayloadBuilder.publicationDecision(
            conditions: makeConditions(referenceDate: referenceDate, dataStartDay: 26),
            existingSummary: nil, referenceDate: referenceDate, timeZone: timeZone
        )
        guard case let .publish(summary) = decision else {
            return XCTFail("Expected the upcoming evening")
        }
        XCTAssertEqual(summary.nights.first?.observingDate, date(day: 26))
    }

    func testFreshPostMidnightPublicationPreservesOnlyValidExistingPayload() {
        let referenceDate = date(day: 26, hour: 1)
        let conditions = makeConditions(referenceDate: referenceDate, dataStartDay: 26)
        let valid = makeSummary(
            generatedAt: date(day: 26),
            nights: shiftedNights(startDay: 25)
        )
        assertPreserved(conditions: conditions, existing: valid, referenceDate: referenceDate)

        assertUnavailable(conditions: conditions, existing: nil, referenceDate: referenceDate)
        assertUnavailable(
            conditions: conditions,
            existing: makeSummary(
                generatedAt: date(day: 25, hour: 21).addingTimeInterval(-1),
                nights: shiftedNights(startDay: 25)
            ),
            referenceDate: referenceDate
        )
        assertUnavailable(
            conditions: conditions,
            existing: makeSummary(
                generatedAt: date(day: 25, hour: 23), latitude: 47.6,
                nights: shiftedNights(startDay: 25)
            ),
            referenceDate: referenceDate
        )
        assertUnavailable(
            conditions: conditions,
            existing: makeSummary(
                generatedAt: date(day: 25, hour: 23), nights: shiftedNights(startDay: 24)
            ),
            referenceDate: referenceDate
        )
        assertUnavailable(
            conditions: conditions,
            existing: makeSummary(
                generatedAt: date(day: 25, hour: 23),
                nights: Array(shiftedNights(startDay: 25).prefix(2))
            ),
            referenceDate: referenceDate
        )
        let ordered = shiftedNights(startDay: 25)
        assertUnavailable(
            conditions: conditions,
            existing: makeSummary(
                generatedAt: date(day: 25, hour: 23),
                nights: [ordered[0], ordered[2], ordered[1]]
            ),
            referenceDate: referenceDate
        )
        assertUnavailable(
            conditions: conditions,
            existing: makeSummary(
                generatedAt: date(day: 25, hour: 23), status: .unavailable,
                nights: shiftedNights(startDay: 25)
            ),
            referenceDate: referenceDate
        )
    }

    func testInsufficientDailyDataPublishesUnavailableWithoutIndexingPastEnd() {
        let referenceDate = date(day: 25, hour: 20)
        let decision = ThreeNightOutlookWidgetPayloadBuilder.publicationDecision(
            conditions: makeConditions(
                referenceDate: referenceDate, dailyCount: 2
            ),
            existingSummary: nil, referenceDate: referenceDate, timeZone: timeZone
        )
        guard case .unavailable = decision else {
            return XCTFail("Expected unavailable for a partial three-night forecast")
        }
    }

    func testNoBestNightWhenEveryRowIsUnavailable() {
        let summary = makeSummary(nights: makeNights().map {
            night(
                label: $0.displayLabel, day: calendar.component(.day, from: $0.observingDate),
                score: nil, status: .unavailable, isBest: false
            )
        })
        XCTAssertFalse(summary.nights.contains(where: \.isBestNight))
        XCTAssertNil(ThreeNightOutlookWidgetPayloadBuilder.bestNightIndex(in: summary.nights))
    }

    func testHighestScoreWinsWithoutChangingOrder() {
        let nights = [
            night(label: "Tonight", day: 25, score: 72, status: .available, isBest: false),
            night(label: "Tomorrow", day: 26, score: 91, status: .available, isBest: false),
            night(label: "Day After", day: 27, score: 80, status: .available, isBest: false)
        ]
        XCTAssertEqual(ThreeNightOutlookWidgetPayloadBuilder.bestNightIndex(in: nights), 1)
        XCTAssertEqual(nights.map(\.displayLabel), ["Tonight", "Tomorrow", "Day After"])
    }

    func testBestNightTieSelectsEarliest() {
        let nights = [
            night(label: "Tonight", day: 25, score: 91, status: .available, isBest: false),
            night(label: "Tomorrow", day: 26, score: 91, status: .available, isBest: false),
            night(label: "Day After", day: 27, score: 80, status: .available, isBest: false)
        ]
        XCTAssertEqual(ThreeNightOutlookWidgetPayloadBuilder.bestNightIndex(in: nights), 0)
    }

    func testPresentationUsesExplicitMissingWindowStatus() {
        let row = WidgetThreeNightOutlookNight(
            id: "Tonight", displayLabel: "Tonight", observingDate: date(day: 25),
            score: 75, verdict: "Good", scoreTone: .informational,
            astronomicalNightStart: date(day: 25, hour: 22),
            astronomicalNightEnd: date(day: 26, hour: 4), bestWindow: nil,
            statusText: "No best window available", status: .available, isBestNight: true
        )
        XCTAssertEqual(
            WidgetThreeNightOutlookPresentation.windowText(
                for: row, timeZone: timeZone, compact: false
            ),
            "No best window available"
        )
        XCTAssertEqual(
            WidgetThreeNightOutlookPresentation.windowText(
                for: row, timeZone: timeZone, compact: true
            ),
            "No best window available"
        )
    }

    func testRegularAndCompactMinimalBestWindowWording() {
        let row = night(
            label: "Tonight", day: 25, score: 75,
            status: .available, isBest: true
        )
        let range = DateFormatters.formatTimeRange(
            from: date(day: 25, hour: 23),
            to: date(day: 26, hour: 1),
            in: timeZone
        ).replacingOccurrences(of: " ", with: "\u{00A0}")

        XCTAssertEqual(
            WidgetThreeNightOutlookPresentation.windowText(
                for: row, timeZone: timeZone, compact: false
            ),
            "Best window \(range)"
        )
        let compactAndMinimal = WidgetThreeNightOutlookPresentation.windowText(
            for: row, timeZone: timeZone, compact: true
        )
        XCTAssertEqual(compactAndMinimal, "Best \(range)")
        XCTAssertTrue(compactAndMinimal.contains("PM"))
        XCTAssertTrue(compactAndMinimal.contains("AM"))
        XCTAssertFalse(compactAndMinimal.contains("11:00 PM"))
        XCTAssertFalse(compactAndMinimal.contains("1:00 AM"))
    }

    func testTimelineAndExtensionArchitectureSourceConstraints() throws {
        let provider = try source("Sources/Widgets/ThreeNightOutlookTimelineProvider.swift")
        XCTAssertTrue(provider.contains("timelineReevaluationInterval: TimeInterval = 3600"))
        let widgetSources = try [
            "Sources/Widgets/ThreeNightOutlookTimelineProvider.swift",
            "Sources/Widgets/ThreeNightOutlookWidgetMediumEntryView.swift",
            "Sources/Widgets/WidgetThreeNightOutlookPresentation.swift"
        ].map(source).joined()
        for forbidden in [
            "NightQualityAnalyzer", "TargetRecommendationService", "widgetURL",
            "Link(", ".system(size:", ".minimumScaleFactor", ".lineLimit(",
            ".dynamicTypeSize(", ".truncationMode("
        ] {
            XCTAssertFalse(widgetSources.contains(forbidden), forbidden)
        }
        XCTAssertTrue(provider.contains("SharedConditionsRepository().conditions"))
        XCTAssertTrue(provider.contains("ThreeNightOutlookWidgetPayloadBuilder.publicationDecision"))
        XCTAssertTrue(provider.contains("saveWidgetThreeNightOutlookSummaryAsync"))
        XCTAssertTrue(provider.contains("cachedSummary.locationMatches(location)"))
        XCTAssertTrue(provider.contains("cachedSummary.matchesCurrentObservingNight"))
        XCTAssertTrue(provider.contains("context.isPreview"))
        XCTAssertTrue(provider.contains("Timeline invocation"))
        XCTAssertTrue(provider.contains("Using matching last-known-good Outlook summary"))
        XCTAssertFalse(provider.contains("payloadMaximumAge"))

        let conditionsCall = try XCTUnwrap(
            provider.range(of: "SharedConditionsRepository().conditions")
        )
        let fallbackCheck = try XCTUnwrap(
            provider.range(of: "cachedSummary.locationMatches(location)")
        )
        XCTAssertLessThan(
            provider.distance(from: provider.startIndex, to: conditionsCall.lowerBound),
            provider.distance(from: provider.startIndex, to: fallbackCheck.lowerBound)
        )
    }

    func testEveryLayoutCandidateRetainsThreeRowLoopAndSharedIdentity() throws {
        let view = try source("Sources/Widgets/ThreeNightOutlookWidgetMediumEntryView.swift")
        let candidates = contentCandidateArguments(in: view).filter {
            $0.contains("showsSymbol: true") || $0.contains("showsSymbol: false")
        }
        XCTAssertEqual(candidates.count, 7)
        XCTAssertTrue(candidates.allSatisfy { $0.contains("showsSymbol: true") })
        XCTAssertFalse(candidates.contains { $0.contains("showsSymbol: false") })
        XCTAssertEqual(
            view.components(separatedBy: "ForEach(Array(summary.nights.enumerated())").count - 1,
            1
        )
        XCTAssertTrue(view.contains("Image(systemName: WidgetAppIdentity.symbol)"))
        XCTAssertNotEqual(WidgetAppIdentity.symbol, "calendar")
    }

    func testAllHomeScreenWidgetsUseSharedIdentityIncludingUnavailableState() throws {
        let phaseOneSources = try [
            "Sources/Widgets/NightConditionsWidget.swift",
            "Sources/Widgets/NightConditionsWidgetMediumEntryView.swift",
            "Sources/Widgets/NightConditionsWidgetSmallEntryView.swift"
        ].map(source)
        let phaseTwoSources = try [
            "Sources/Widgets/TonightTargetsWidget.swift",
            "Sources/Widgets/TonightTargetsWidgetMediumEntryView.swift"
        ].map(source)
        let phaseThreeView = try source(
            "Sources/Widgets/ThreeNightOutlookWidgetMediumEntryView.swift"
        )
        let phaseThreeWidget = try source(
            "Sources/Widgets/ThreeNightOutlookWidget.swift"
        )

        for widgetSource in phaseOneSources + phaseTwoSources
            + [phaseThreeView, phaseThreeWidget] {
            XCTAssertTrue(widgetSource.contains("WidgetAppIdentity.symbol"))
        }
        XCTAssertTrue(phaseThreeWidget.contains(
            "systemImage: WidgetAppIdentity.symbol"
        ))

        let phaseThreeIdentitySources = try [
            "Sources/Widgets/ThreeNightOutlookWidgetMediumEntryView.swift",
            "Sources/Widgets/ThreeNightOutlookWidget.swift",
            "Sources/Widgets/WidgetThreeNightOutlookPresentation.swift"
        ].map(source).joined(separator: "\n")
        XCTAssertFalse(phaseThreeIdentitySources.contains("\"calendar\""))
    }

    func testLayoutModeByDynamicTypeSize() {
        for size in [
            DynamicTypeSize.xSmall, .small, .medium, .large, .xLarge, .xxLarge
        ] {
            XCTAssertEqual(
                ThreeNightOutlookLayoutPolicy.mode(for: size),
                .standardWithLocationPreference,
                "\(size) should use the standard location hierarchy"
            )
        }
        XCTAssertEqual(
            ThreeNightOutlookLayoutPolicy.mode(for: .xxxLarge),
            .largestStandard
        )
        for size in [
            DynamicTypeSize.accessibility1, .accessibility2, .accessibility3,
            .accessibility4, .accessibility5
        ] {
            XCTAssertEqual(
                ThreeNightOutlookLayoutPolicy.mode(for: size),
                .accessibility,
                "\(size) should use the accessibility hierarchy"
            )
        }
    }

    func testStandardCandidateOrderIncludesCompactLocationFallback() throws {
        let view = try source("Sources/Widgets/ThreeNightOutlookWidgetMediumEntryView.swift")
        let section = try sourceSection(
            in: view,
            from: "private func standardCandidates()",
            through: "private func largestStandardCandidates()"
        )
        XCTAssertEqual(
            normalizedCandidates(in: section),
            [
                "style: .regular, showsLocation: true, showsVerdict: true, showsSymbol: true",
                "style: .compact, showsLocation: true, showsVerdict: true, showsSymbol: true",
                "style: .compact, showsLocation: false, showsVerdict: true, showsSymbol: true",
                "style: .minimal, showsLocation: false, showsVerdict: false, showsSymbol: true"
            ]
        )
    }

    func testLargestStandardCandidateOrderStartsCompactWithoutOptionalText() throws {
        let view = try source("Sources/Widgets/ThreeNightOutlookWidgetMediumEntryView.swift")
        let section = try sourceSection(
            in: view,
            from: "private func largestStandardCandidates()",
            through: "private func accessibilityCandidates()"
        )
        XCTAssertEqual(
            normalizedCandidates(in: section),
            [
                "style: .compact, showsLocation: false, showsVerdict: false, showsSymbol: true",
                "style: .minimal, showsLocation: false, showsVerdict: false, showsSymbol: true"
            ]
        )
    }

    func testAccessibilityCandidatesOmitLocationAndVerdicts() throws {
        let view = try source("Sources/Widgets/ThreeNightOutlookWidgetMediumEntryView.swift")
        let section = try sourceSection(
            in: view,
            from: "private func accessibilityCandidates()",
            through: "private func content"
        )
        let candidates = normalizedCandidates(in: section)
        XCTAssertEqual(candidates, [
            "style: .minimal, showsLocation: false, showsVerdict: false, showsSymbol: true"
        ])
    }

    func testPhaseThreeViewKeepsForbiddenLayoutTechniquesOut() throws {
        let view = try source(
            "Sources/Widgets/ThreeNightOutlookWidgetMediumEntryView.swift"
        )
        for forbidden in [
            ".system(size:", ".lineLimit(", ".minimumScaleFactor",
            ".truncationMode(", ".dynamicTypeSize(", "GeometryReader",
            ".clipped(", ".clipShape(", "padding(-"
        ] {
            XCTAssertFalse(view.contains(forbidden), forbidden)
        }
        XCTAssertTrue(view.contains("showsLocation: true"))
        XCTAssertTrue(view.contains("showsLocation: false"))
    }

    func testReloadServiceIncludesAllHomeScreenWidgetKinds() throws {
        let source = try source("Sources/SharedCode/Core/Services/WidgetReloadService.swift")
        for kind in ["NightConditionsWidget", "TonightTargetsWidget", "ThreeNightOutlookWidget"] {
            XCTAssertTrue(source.contains(kind))
        }
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func date(day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: day, hour: hour))!
    }

    private func night(
        label: String, day: Int, score: Int?, status: WidgetThreeNightOutlookNightStatus,
        isBest: Bool, bestWindow: NightQualityAssessment.TimeWindow? = nil,
        statusText: String = "Best window"
    ) -> WidgetThreeNightOutlookNight {
        WidgetThreeNightOutlookNight(
            id: label, displayLabel: label, observingDate: date(day: day),
            score: score, verdict: score == nil ? "Unavailable" : "Good",
            scoreTone: score == nil ? nil : .informational,
            astronomicalNightStart: date(day: day, hour: 22),
            astronomicalNightEnd: date(day: day + 1, hour: 4),
            bestWindow: bestWindow ?? (score == nil ? nil : .init(
                start: date(day: day, hour: 23), end: date(day: day + 1, hour: 1)
            )),
            statusText: statusText, status: status, isBestNight: isBest
        )
    }

    private func makeNights() -> [WidgetThreeNightOutlookNight] {
        [
            night(label: "Tonight", day: 25, score: 87, status: .available, isBest: true),
            night(label: "Tomorrow", day: 26, score: 72, status: .available, isBest: false),
            night(label: "Day After", day: 27, score: 48, status: .available, isBest: false)
        ]
    }

    private func shiftedNights(startDay: Int) -> [WidgetThreeNightOutlookNight] {
        [
            night(label: "Tonight", day: startDay, score: 87, status: .available, isBest: true),
            night(label: "Tomorrow", day: startDay + 1, score: 72, status: .available, isBest: false),
            night(label: "Day After", day: startDay + 2, score: 48, status: .available, isBest: false)
        ]
    }

    private func makeSummary(
        generatedAt: Date? = nil, locationName: String = "Home",
        latitude: Double = 45.5,
        savedLocationID: UUID? = nil,
        status: WidgetThreeNightOutlookStatus = .available,
        nights: [WidgetThreeNightOutlookNight]? = nil
    ) -> WidgetThreeNightOutlookSummary {
        WidgetThreeNightOutlookSummary(
            generatedAt: generatedAt ?? date(day: 25, hour: 20),
            locationName: locationName, latitude: latitude, longitude: -122.7,
            savedLocationID: savedLocationID,
            timeZoneIdentifier: timeZone.identifier, status: status,
            nights: nights ?? makeNights()
        )
    }

    private func makeConditions(
        referenceDate: Date,
        dataStartDay: Int = 25,
        dailyCount: Int = 4,
        locationID: UUID? = nil
    ) -> ViewingConditions {
        let start = date(day: dataStartDay)
        let forecasts = (0..<(4 * 24)).map { offset in
            HourlyForecast(
                time: start.addingTimeInterval(TimeInterval(offset) * 3600),
                cloudCover: 20 + offset % 10, humidity: 45, windSpeed: 2,
                windDirection: 180, temperature: 12, dewPoint: 5, visibility: 20_000
            )
        }
        let sunEvents = (0..<dailyCount).map { offset in
            let day = dataStartDay + offset
            return SunEvents(
                sunrise: date(day: day, hour: 6), sunset: date(day: day, hour: 20),
                civilTwilightBegin: date(day: day, hour: 5),
                civilTwilightEnd: date(day: day, hour: 21),
                nauticalTwilightBegin: date(day: day, hour: 4),
                nauticalTwilightEnd: date(day: day, hour: 21),
                astronomicalTwilightBegin: date(day: day, hour: 4),
                astronomicalTwilightEnd: date(day: day, hour: 22)
            )
        }
        return ViewingConditions(
            fetchedAt: referenceDate,
            location: CachedLocation(
                id: locationID, name: "Home", latitude: 45.5, longitude: -122.7
            ),
            hourlyForecasts: forecasts, dailySunEvents: sunEvents,
            dailyMoonInfo: (0..<dailyCount).map {
                MoonInfo(
                    phase: 0.2, phaseName: "Waxing", altitude: 10,
                    illumination: 20 + $0, emoji: "🌒"
                )
            },
            issPasses: [], fogScore: FogScore(score: 0, factors: []),
            timeZoneIdentifier: timeZone.identifier
        )
    }

    private func resolve(
        _ summary: WidgetThreeNightOutlookSummary?,
        _ location: SelectedLocation?,
        at date: Date
    ) -> ThreeNightOutlookResolvedState {
        ThreeNightOutlookEntryResolver.resolve(
            summary: summary, selectedLocation: location, referenceDate: date
        )
    }

    private func selectedLocation(
        id: UUID? = nil,
        latitude: Double = 45.5,
        longitude: Double = -122.7,
        source: SelectedLocation.Source = .currentGPS
    ) -> SelectedLocation {
        SelectedLocation(
            source: source,
            id: id,
            name: "Home",
            latitude: latitude,
            longitude: longitude
        )
    }

    private func assertPreserved(
        conditions: ViewingConditions,
        existing: WidgetThreeNightOutlookSummary?,
        referenceDate: Date,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let decision = ThreeNightOutlookWidgetPayloadBuilder.publicationDecision(
            conditions: conditions, existingSummary: existing,
            referenceDate: referenceDate, timeZone: timeZone
        )
        guard case .preserveExisting = decision else {
            return XCTFail("Expected preserveExisting", file: file, line: line)
        }
    }

    private func assertUnavailable(
        conditions: ViewingConditions,
        existing: WidgetThreeNightOutlookSummary?,
        referenceDate: Date,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let decision = ThreeNightOutlookWidgetPayloadBuilder.publicationDecision(
            conditions: conditions, existingSummary: existing,
            referenceDate: referenceDate, timeZone: timeZone
        )
        guard case .unavailable = decision else {
            return XCTFail("Expected unavailable", file: file, line: line)
        }
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func sourceSection(
        in source: String, from startMarker: String, through endMarker: String
    ) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMarker)?.lowerBound)
        let end = try XCTUnwrap(
            source.range(of: endMarker, range: start..<source.endIndex)?.upperBound
        )
        return String(source[start..<end])
    }

    private func contentCandidateArguments(in source: String) -> [String] {
        let marker = "content("
        var values: [String] = []
        var start = source.startIndex
        while let markerRange = source.range(of: marker, range: start..<source.endIndex),
              let end = source.range(of: ")", range: markerRange.upperBound..<source.endIndex) {
            values.append(String(source[markerRange.upperBound..<end.lowerBound]))
            start = end.upperBound
        }
        return values
    }

    private func normalizedCandidates(in source: String) -> [String] {
        contentCandidateArguments(in: source).map {
            $0.components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
    }
}

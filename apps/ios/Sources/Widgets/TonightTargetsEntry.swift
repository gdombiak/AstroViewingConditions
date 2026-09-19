import Foundation
import SharedCode
import WidgetKit

struct TonightTargetsEntry: TimelineEntry, Sendable {
    enum State: Sendable {
        case available(WidgetTonightTargetsSummary)
        case noTargets
        case unavailable(UnavailableReason)
    }

    enum UnavailableReason: Sendable {
        case noLocation
        case noCache
        case stale
        case locationMismatch
        case observingNightMismatch
        case unavailable

        var message: String {
            switch self {
            case .noLocation:
                return "Open Astro Conditions to choose a location"
            case .noCache:
                return "Open Astro Conditions to update"
            case .stale:
                return "Targets need an update"
            case .locationMismatch:
                return "No targets available for this location"
            case .observingNightMismatch:
                return "Tonight’s targets need an update"
            case .unavailable:
                return "Targets are unavailable"
            }
        }
    }

    let date: Date
    let state: State
    let dataStatus: WidgetDataStatus?

    init(date: Date, state: State, dataStatus: WidgetDataStatus? = nil) {
        self.date = date
        self.state = state
        self.dataStatus = dataStatus
    }

    static var placeholder: TonightTargetsEntry {
        TonightTargetsEntry(
            date: Date(),
            state: .available(.preview),
            dataStatus: nil
        )
    }

    static func make(
        summary: WidgetTonightTargetsSummary,
        date: Date,
        dataStatus: WidgetDataStatus
    ) -> TonightTargetsEntry {
        switch summary.status {
        case .available where !summary.targets.isEmpty:
            return TonightTargetsEntry(
                date: date,
                state: .available(summary),
                dataStatus: dataStatus
            )
        case .noTargets:
            return TonightTargetsEntry(
                date: date,
                state: .noTargets,
                dataStatus: dataStatus
            )
        case .unavailable, .available:
            return TonightTargetsEntry(
                date: date,
                state: .unavailable(.unavailable)
            )
        }
    }
}

struct TonightTargetsUnavailableEntrySelection {
    let entry: TonightTargetsEntry
    let displayedSummary: WidgetTonightTargetsSummary
    let shouldSaveCandidate: Bool
}

/// Pure selection shared by the provider and its behavioral tests.
enum TonightTargetsUnavailableEntrySelector {
    static func select(
        candidate: WidgetTonightTargetsSummary,
        existing: WidgetTonightTargetsSummary?,
        targetLocation: CachedLocation,
        referenceDate: Date,
        candidateDataStatus: WidgetDataStatus
    ) -> TonightTargetsUnavailableEntrySelection {
        let shouldSaveCandidate = TonightTargetsPersistencePolicy.shouldSave(
            candidate: candidate,
            existing: existing,
            targetLocation: targetLocation,
            referenceDate: referenceDate
        )

        if !shouldSaveCandidate,
           let existing,
           TonightTargetsPersistencePolicy.isValidLastKnownGood(
            existing,
            for: targetLocation,
            referenceDate: referenceDate
           ) {
            return TonightTargetsUnavailableEntrySelection(
                entry: TonightTargetsEntry.make(
                    summary: existing,
                    date: referenceDate,
                    dataStatus: .fallback(summary: existing)
                ),
                displayedSummary: existing,
                shouldSaveCandidate: false
            )
        }

        return TonightTargetsUnavailableEntrySelection(
            entry: TonightTargetsEntry.make(
                summary: candidate,
                date: referenceDate,
                dataStatus: candidateDataStatus
            ),
            displayedSummary: candidate,
            shouldSaveCandidate: shouldSaveCandidate
        )
    }
}

extension WidgetTonightTargetsSummary {
    static let preview: WidgetTonightTargetsSummary = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let observingDate = calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 25)
        )!
        let nightStart = calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 25, hour: 22)
        )!
        let nightEnd = calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 26, hour: 4)
        )!
        let names = [
            "NGC 869/884 Double Cluster",
            "M13 Hercules Cluster",
            "Saturn"
        ]

        return WidgetTonightTargetsSummary(
            generatedAt: observingDate,
            locationName: "Home",
            latitude: 45.5,
            longitude: -122.7,
            timeZoneIdentifier: calendar.timeZone.identifier,
            observingDate: observingDate,
            astronomicalNightStart: nightStart,
            astronomicalNightEnd: nightEnd,
            status: .available,
            targets: names.enumerated().map { index, name in
                WidgetTonightTargetSummary(
                    targetID: "preview-\(index)",
                    displayName: name,
                    categoryLabel: index == 2 ? "Planet" : "Open Cluster",
                    score: [91, 84, 78][index],
                    scoreTone: [.positive, .positive, .informational][index],
                    bestTime: nightStart.addingTimeInterval(
                        TimeInterval(index + 1) * 3600
                    ),
                    positionLabel: ["NE · 62°", "S · 54°", "SE · 38°"][index]
                )
            }
        )
    }()
}

import Foundation
import SharedCode
import WidgetKit

struct ThreeNightOutlookEntry: TimelineEntry, Sendable {
    enum State: Sendable {
        case available(WidgetThreeNightOutlookSummary)
        case unavailable(UnavailableReason)
    }

    enum UnavailableReason: Sendable {
        case noLocation, noCache, stale, locationMismatch, observingNightMismatch, unavailable

        var message: String {
            switch self {
            case .noLocation: "Open Astro Conditions to choose a location"
            case .noCache: "Open Astro Conditions to update"
            case .stale: "Outlook needs an update"
            case .locationMismatch: "Outlook needs an update for this location"
            case .observingNightMismatch: "Three-night outlook needs an update"
            case .unavailable: "Outlook is unavailable"
            }
        }
    }

    let date: Date
    let state: State

    static var placeholder: Self {
        .init(date: Date(), state: .available(.preview))
    }
}

extension WidgetThreeNightOutlookSummary {
    static let preview: Self = {
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: Date())
        let values = [(87, "Excellent"), (72, "Good"), (48, "Fair")]
        return Self(
            generatedAt: Date(), locationName: "Home", latitude: 45.5, longitude: -122.7,
            timeZoneIdentifier: timeZone.identifier, status: .available,
            nights: values.enumerated().map { index, value in
                let date = calendar.date(byAdding: .day, value: index, to: start)!
                return WidgetThreeNightOutlookNight(
                    id: "\(index)", displayLabel: ["Tonight", "Tomorrow", "Day After"][index],
                    observingDate: date, score: value.0, verdict: value.1,
                    scoreTone: [.positive, .informational, .caution][index],
                    astronomicalNightStart: calendar.date(
                        byAdding: .hour, value: 21 + index, to: date
                    ),
                    astronomicalNightEnd: calendar.date(
                        byAdding: .hour, value: 28 + index, to: date
                    ),
                    bestWindow: .init(
                        start: calendar.date(byAdding: .hour, value: 22 + index, to: date)!,
                        end: calendar.date(byAdding: .hour, value: 25 + index, to: date)!
                    ),
                    statusText: "Best window", status: .available, isBestNight: index == 0
                )
            }
        )
    }()
}

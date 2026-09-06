import Foundation
import SharedCode
import WidgetKit

struct NightConditionsEntry: TimelineEntry, Sendable {
    enum State: Sendable {
        case available(WidgetNightSummary)
        case unavailable(UnavailableReason)
    }

    enum UnavailableReason: Sendable {
        case noLocation
        case noForecast
        case staleForecast
        case locationUnavailable

        var message: String {
            switch self {
            case .noLocation:
                return "Open Astro Conditions to choose a location"
            case .noForecast:
                return "Open Astro Conditions to update"
            case .staleForecast:
                return "Forecast needs an update"
            case .locationUnavailable:
                return "No forecast available"
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

    static var placeholder: NightConditionsEntry {
        NightConditionsEntry(
            date: Date(),
            state: .available(
                WidgetNightSummary(
                    generatedAt: Date(),
                    locationName: "Home",
                    latitude: 0,
                    longitude: 0,
                    timeZoneIdentifier: nil,
                    score: 73,
                    verdict: "Good",
                    earlyQuality: "Fair",
                    lateQuality: "Good",
                    trend: .improving,
                    bestWindow: nil,
                    primaryMessage: "Clouds early",
                    factors: [
                        NightQualityDisplayFactor(kind: .clouds, label: "Clouds", value: "28%", tone: .favorable),
                        NightQualityDisplayFactor(kind: .seeing, label: "Seeing", value: "Good", tone: .favorable),
                        NightQualityDisplayFactor(kind: .transparency, label: "Transparency", value: "Good", tone: .favorable)
                    ],
                    hasAstronomicalNight: true
                )
            ),
            dataStatus: nil
        )
    }

    static let layoutPreviewSummary: WidgetNightSummary = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let start = calendar.date(from: .init(year: 2026, month: 7, day: 25, hour: 22))!
        let end = calendar.date(from: .init(year: 2026, month: 7, day: 26, hour: 0))!

        return WidgetNightSummary(
            generatedAt: start,
            locationName: "Ivan",
            latitude: 45.5,
            longitude: -122.7,
            timeZoneIdentifier: "America/Los_Angeles",
            score: 20,
            verdict: "Poor",
            earlyQuality: "Fair",
            lateQuality: "Poor",
            trend: .stable,
            bestWindow: .init(start: start, end: end),
            primaryMessage: "Heavy clouds are likely to block the view.",
            factors: [
                NightQualityDisplayFactor(kind: .clouds, label: "Clouds", value: "78%", tone: .limiting),
                NightQualityDisplayFactor(kind: .seeing, label: "Seeing", value: "Excellent", tone: .favorable),
                NightQualityDisplayFactor(kind: .transparency, label: "Transparency", value: "Poor", tone: .limiting)
            ],
            hasAstronomicalNight: true
        )
    }()

    static let smallHeaderPreviewSummary = makeSmallHeaderPreviewSummary(verdict: "Good")
    static let smallHeaderExcellentPreviewSummary = makeSmallHeaderPreviewSummary(verdict: "Excellent")

    private static func makeSmallHeaderPreviewSummary(verdict: String) -> WidgetNightSummary {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let start = calendar.date(from: .init(year: 2026, month: 7, day: 25, hour: 23))!
        let end = calendar.date(from: .init(year: 2026, month: 7, day: 26, hour: 4))!

        return WidgetNightSummary(
            generatedAt: start,
            locationName: "Ivan",
            latitude: 45.5,
            longitude: -122.7,
            timeZoneIdentifier: "America/Los_Angeles",
            score: 73,
            verdict: verdict,
            earlyQuality: "Good",
            lateQuality: "Fair",
            trend: .stable,
            bestWindow: .init(start: start, end: end),
            primaryMessage: "Clouds may affect the view later.",
            factors: [
                NightQualityDisplayFactor(kind: .clouds, label: "Clouds", value: "32%", tone: .favorable),
                NightQualityDisplayFactor(kind: .seeing, label: "Seeing", value: "Good", tone: .favorable),
                NightQualityDisplayFactor(kind: .transparency, label: "Transparency", value: "Fair", tone: .neutral)
            ],
            hasAstronomicalNight: true
        )
    }
}

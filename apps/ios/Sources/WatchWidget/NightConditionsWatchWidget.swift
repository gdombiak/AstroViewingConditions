import WidgetKit
import SwiftUI
import SharedCode
import os.log

private let widgetLogger = Logger(subsystem: "com.astroviewing.conditions.watchwidget", category: "WatchWidget")
/// Re-evaluate timeline hourly so a later watch-app reload is not the only refresh path.
private let watchWidgetTimelineInterval: TimeInterval = 3600

struct NightConditionsEntry: TimelineEntry, Sendable {
    enum State: Sendable, Equatable {
        case available(
            assessment: NightQualityAssessment,
            headlineScore: Int,
            scorePresentationMode: WatchHeadlineScorePresentationMode
        )
        /// Live timeline/snapshot with no usable companion pair (not gallery placeholder).
        case unavailable
    }

    let date: Date
    let state: State

    var isUnavailable: Bool {
        if case .unavailable = state { return true }
        return false
    }

    static func unavailable(at date: Date = Date()) -> NightConditionsEntry {
        NightConditionsEntry(date: date, state: .unavailable)
    }

    /// WidgetKit gallery / `placeholder(in:)` only — synthetic example data, never a live fallback.
    static var placeholder: NightConditionsEntry {
        let assessment = NightQualityAssessment(
            rating: .good,
            summary: "Good conditions for stargazing tonight.",
            details: NightQualityAssessment.Details(
                cloudCoverScore: 25,
                fogScoreAvg: 15,
                moonIlluminationAvg: 12,
                windSpeedAvg: 2.5
            ),
            bestWindow: nil,
            hourlyRatings: [],
            nightStart: Date(),
            nightEnd: Date().addingTimeInterval(8 * 3600),
            trend: .stable,
            firstHalfScore: nil,
            secondHalfScore: nil
        )
        return NightConditionsEntry(
            date: Date(),
            state: .available(
                assessment: assessment,
                headlineScore: assessment.calculatedScore,
                scorePresentationMode: .nightConditionsFallback
            )
        )
    }
}

struct WatchProvider: TimelineProvider {
    func placeholder(in context: Context) -> NightConditionsEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @Sendable @escaping (NightConditionsEntry) -> Void) {
        // Capture Bool only — TimelineProviderContext is not Sendable.
        let isPreview = context.isPreview
        Task { @Sendable in
            if isPreview {
                completion(.placeholder)
                return
            }
            completion(await buildEntry())
        }
    }

    func getTimeline(in context: Context, completion: @Sendable @escaping (Timeline<NightConditionsEntry>) -> Void) {
        Task { @Sendable in
            let entry = await buildEntry()
            let nextUpdate = Date().addingTimeInterval(watchWidgetTimelineInterval)
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }

    /// Complications are **read-only companions** of the watch app App Group pair.
    ///
    /// They must not fetch weather or write `watchNightConditions` alone: an unpaired
    /// conditions write drops OQ association and surfaces the night-only score
    /// (e.g. 98 instead of LP-adjusted 91). Architecture: consume synchronized state only.
    /// Missing/stale/mismatched companion state → explicit `.unavailable`, never `.placeholder`.
    private func buildEntry(referenceDate: Date = Date()) async -> NightConditionsEntry {
        let selected = AppGroupStorage.loadSelectedLocationForWidget()
        let cached = await AppGroupStorage.loadWatchNightConditionsAsync()

        switch WatchComplicationCompanionDisplayPolicy.evaluate(
            selectedLocation: selected,
            conditions: cached,
            referenceDate: referenceDate
        ) {
        case let .failure(reason):
            widgetLogger.info("Companion state unavailable: \(reason.rawValue, privacy: .public)")
            return .unavailable(at: referenceDate)
        case let .success(context):
            widgetLogger.info("Using companion watch conditions for active observing night")
            return await buildAvailableEntry(from: context, referenceDate: referenceDate)
        }
    }

    /// Scores the ActiveObservingNight-selected night (not calendar `startOfDay`).
    private func buildAvailableEntry(
        from context: WatchComplicationCompanionDisplayContext,
        referenceDate: Date
    ) async -> NightConditionsEntry {
        let assessment = context.activeNight.context.nightQuality
        let document = await AppGroupStorage.loadWatchObservingQualityAsync()
        let resolved = WatchComplicationHeadlineResolver.resolve(
            conditions: context.conditions,
            document: document,
            selectedLocation: context.selected,
            nightScore: assessment.calculatedScore
        )
        return NightConditionsEntry(
            date: referenceDate,
            state: .available(
                assessment: assessment,
                headlineScore: resolved.score,
                scorePresentationMode: resolved.presentationMode
            )
        )
    }
}

struct WatchWidgetEntryView: View {
    var entry: NightConditionsEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch entry.state {
        case .unavailable:
            unavailableBody
        case let .available(assessment, headlineScore, scorePresentationMode):
            availableBody(
                assessment: assessment,
                headlineScore: headlineScore,
                scorePresentationMode: scorePresentationMode
            )
        }
    }

    @ViewBuilder
    private func availableBody(
        assessment: NightQualityAssessment,
        headlineScore: Int,
        scorePresentationMode: WatchHeadlineScorePresentationMode
    ) -> some View {
        switch family {
        case .accessoryCircular:
            CircularComplicationView(
                assessment: assessment,
                headlineScore: headlineScore,
                scorePresentationMode: scorePresentationMode
            )
            .containerBackground(.clear, for: .widget)
        case .accessoryRectangular:
            RectangularComplicationView(
                assessment: assessment,
                headlineScore: headlineScore,
                scorePresentationMode: scorePresentationMode
            )
            .containerBackground(.clear, for: .widget)
        case .accessoryInline:
            InlineComplicationView(
                assessment: assessment,
                headlineScore: headlineScore,
                scorePresentationMode: scorePresentationMode
            )
            .containerBackground(.clear, for: .widget)
        case .accessoryCorner:
            CornerComplicationView(
                assessment: assessment,
                headlineScore: headlineScore,
                scorePresentationMode: scorePresentationMode
            )
        default:
            CircularComplicationView(
                assessment: assessment,
                headlineScore: headlineScore,
                scorePresentationMode: scorePresentationMode
            )
            .containerBackground(.clear, for: .widget)
        }
    }

    @ViewBuilder
    private var unavailableBody: some View {
        switch family {
        case .accessoryCircular:
            CircularComplicationView.unavailable
                .containerBackground(.clear, for: .widget)
        case .accessoryRectangular:
            RectangularComplicationView.unavailable
                .containerBackground(.clear, for: .widget)
        case .accessoryInline:
            InlineComplicationView.unavailable
                .containerBackground(.clear, for: .widget)
        case .accessoryCorner:
            CornerComplicationView.unavailable
        default:
            CircularComplicationView.unavailable
                .containerBackground(.clear, for: .widget)
        }
    }
}

struct NightConditionsWatchWidget: Widget {
    let kind: String = "NightConditionsWatchWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchProvider()) { entry in
            WatchWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Night Conditions")
        .description("Tonight's stargazing conditions")
        .supportedFamilies([
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryCorner,
        ])
    }
}

@main
struct WatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        NightConditionsWatchWidget()
    }
}

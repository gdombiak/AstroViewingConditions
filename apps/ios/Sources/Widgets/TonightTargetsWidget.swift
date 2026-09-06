import SwiftUI
import WidgetKit

struct TonightTargetsWidget: Widget {
    static let kind = "TonightTargetsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: Self.kind,
            provider: TonightTargetsTimelineProvider()
        ) { entry in
            TonightTargetsWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Tonight’s Targets")
        .description("See the best astronomical targets for tonight.")
        .supportedFamilies([.systemMedium])
    }
}

private struct TonightTargetsWidgetEntryView: View {
    let entry: TonightTargetsEntry

    var body: some View {
        switch entry.state {
        case let .available(summary):
            TonightTargetsWidgetMediumEntryView(
                summary: summary,
                dataStatus: entry.dataStatus,
                referenceDate: entry.date
            )
        case .noTargets:
            TonightTargetsUnavailableView(message: "No recommended targets tonight")
        case let .unavailable(reason):
            TonightTargetsUnavailableView(message: reason.message)
        }
    }
}

private struct TonightTargetsUnavailableView: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Tonight’s Targets", systemImage: WidgetAppIdentity.symbol)
                .font(.headline)
            Spacer(minLength: 0)
            Text(message)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

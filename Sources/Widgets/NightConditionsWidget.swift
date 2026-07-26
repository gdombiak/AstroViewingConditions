import SharedCode
import SwiftUI
import WidgetKit

struct NightConditionsWidget: Widget {
    let kind: String = "NightConditionsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: Provider()
        ) { entry in
            NightConditionsWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Night Conditions")
        .description("View tonight's stargazing conditions at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct NightConditionsWidgetEntryView: View {
    var entry: NightConditionsEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch entry.state {
        case let .available(summary):
            switch family {
            case .systemSmall:
                NightConditionsWidgetSmallEntryView(summary: summary)
            case .systemMedium:
                NightConditionsWidgetMediumEntryView(summary: summary)
            default:
                NightConditionsWidgetSmallEntryView(summary: summary)
            }
        case let .unavailable(reason):
            WidgetUnavailableView(message: reason.message)
        }
    }
}

private struct WidgetUnavailableView: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Tonight at a Glance", systemImage: WidgetAppIdentity.symbol)
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

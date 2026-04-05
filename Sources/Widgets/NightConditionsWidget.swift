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
        switch family {
        case .systemSmall:
            NightConditionsWidgetSmallEntryView(assessment: entry.assessment)
        case .systemMedium:
            NightConditionsWidgetMediumEntryView(assessment: entry.assessment)
        default:
            NightConditionsWidgetSmallEntryView(assessment: entry.assessment)
        }
    }
}

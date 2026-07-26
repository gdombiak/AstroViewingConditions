import SwiftUI
import WidgetKit

struct ThreeNightOutlookWidget: Widget {
    static let kind = "ThreeNightOutlookWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: ThreeNightOutlookTimelineProvider()) { entry in
            Group {
                switch entry.state {
                case let .available(summary):
                    ThreeNightOutlookWidgetMediumEntryView(summary: summary)
                case let .unavailable(reason):
                    unavailable(reason.message)
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Three-Night Outlook")
        .description("Compare observing conditions for the next three nights.")
        .supportedFamilies([.systemMedium])
    }

    private func unavailable(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                "Three-Night Outlook",
                systemImage: WidgetAppIdentity.symbol
            )
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

#Preview("Standard", as: .systemMedium) {
    ThreeNightOutlookWidget()
} timeline: {
    ThreeNightOutlookEntry.placeholder
}

#Preview("Largest Standard") {
    ThreeNightOutlookWidgetMediumEntryView(summary: .preview)
        .environment(\.dynamicTypeSize, .xxxLarge)
        .padding()
        .frame(width: 360, height: 170)
}

#Preview("Accessibility 3") {
    ThreeNightOutlookWidgetMediumEntryView(summary: .preview)
        .environment(\.dynamicTypeSize, .accessibility3)
        .padding()
        .frame(width: 360, height: 170)
}

#Preview("Unavailable", as: .systemMedium) {
    ThreeNightOutlookWidget()
} timeline: {
    ThreeNightOutlookEntry(date: Date(), state: .unavailable(.noCache))
}

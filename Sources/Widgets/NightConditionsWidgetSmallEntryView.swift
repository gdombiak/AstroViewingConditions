import SharedCode
import SwiftUI
import WidgetKit

struct NightConditionsWidgetSmallEntryView: View {
    let summary: WidgetNightSummary

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        switch density {
        case .regular:
            normalContent
        case .compact:
            compactContent
        case .minimal:
            minimalContent
        }
    }

    private var normalContent: some View {
        ViewThatFits(in: .vertical) {
            content(showConditionSummary: true, showDominantCondition: true, showIdentityIcon: true)
            content(showConditionSummary: true, showDominantCondition: false, showIdentityIcon: true)
            content(showConditionSummary: false, showDominantCondition: false, showIdentityIcon: false)
        }
    }

    private var compactContent: some View {
        ViewThatFits(in: .vertical) {
            compactCandidate(showConditionSummary: true, separateBestLabel: false, showIdentityIcon: true)
            compactCandidate(showConditionSummary: false, separateBestLabel: false, showIdentityIcon: true)
            compactCandidate(showConditionSummary: false, separateBestLabel: true, showIdentityIcon: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var minimalContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            ViewThatFits(in: .horizontal) {
                minimalScoreVerdictHeader(showIdentityIcon: true)
                minimalScoreVerdictHeader(showIdentityIcon: false)
                minimalScoreVerdictStackedHeader
            }

            if let bestWindow = WidgetTonightPresentation.compactBestWindowText(summary.bestWindow, timeZone: timeZone) {
                Text("Best")
                    .font(.caption2.weight(.medium))
                Text(bestWindow)
                    .font(.caption2)
                    .lineLimit(1)
            } else if !summary.hasAstronomicalNight {
                Label("No dark observing window", systemImage: "moon.zzz")
                    .font(.caption2)
                    .lineLimit(2)
            } else {
                Label(summary.primaryMessage, systemImage: "clock.badge.exclamationmark")
                    .font(.caption2)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func minimalScoreVerdictHeader(showIdentityIcon: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(summary.observingQualityScore)")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(scoreColor)
                .accessibilityLabel("Score \(summary.observingQualityScore)")
                .fixedSize(horizontal: true, vertical: false)
            Text(summary.verdict)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(scoreColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            if showIdentityIcon {
                Spacer(minLength: 0)
                identityIcon
            }
        }
    }

    private var minimalScoreVerdictStackedHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(summary.observingQualityScore)")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(scoreColor)
                .accessibilityLabel("Score \(summary.observingQualityScore)")
                .fixedSize(horizontal: true, vertical: false)
            Text(summary.verdict)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(scoreColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func compactCandidate(
        showConditionSummary: Bool,
        separateBestLabel: Bool,
        showIdentityIcon: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                compactScoreVerdictHeader(showIdentityIcon: true)
                compactScoreVerdictHeader(showIdentityIcon: false)
            }

            if showConditionSummary, WidgetTonightPresentation.smallLayoutShowsConditionSummary(for: density) {
                conditionSummaryRow(font: .caption.weight(.medium))
            }

            compactBestWindow(separateLabel: separateBestLabel)
        }
    }

    private func compactScoreVerdictHeader(showIdentityIcon: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(summary.observingQualityScore)")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(scoreColor)
                .accessibilityLabel("Score \(summary.observingQualityScore)")
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Text(summary.verdict)
                .font(.headline.weight(.semibold))
                .foregroundStyle(scoreColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            if showIdentityIcon {
                Spacer(minLength: 0)
                identityIcon
            }
        }
    }

    @ViewBuilder
    private func compactBestWindow(separateLabel: Bool) -> some View {
        if let bestWindow = WidgetTonightPresentation.compactBestWindowText(summary.bestWindow, timeZone: timeZone) {
            if separateLabel {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Best")
                    Text(bestWindow)
                        .lineLimit(1)
                }
                .font(.caption)
            } else {
                Text("Best \(bestWindow)")
                    .font(.caption)
                    .lineLimit(2)
            }
        } else if !summary.hasAstronomicalNight {
            Label("No dark observing window", systemImage: "moon.zzz")
                .font(.caption)
                .lineLimit(2)
        } else {
            Text(summary.primaryMessage)
                .font(.caption)
                .lineLimit(2)
        }
    }

    private func content(
        showConditionSummary: Bool,
        showDominantCondition: Bool,
        showIdentityIcon: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(summary.observingQualityScore)")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(scoreColor)
                    .accessibilityLabel("Score \(summary.observingQualityScore)")
                Text(summary.verdict)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(scoreColor)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if showIdentityIcon {
                    identityIcon
                }
            }

            if showConditionSummary {
                conditionSummaryRow(font: .subheadline.weight(.medium))
            }

            if let bestWindow = WidgetTonightPresentation.bestWindowText(summary.bestWindow, timeZone: timeZone) {
                Label("Best \(bestWindow)", systemImage: "clock")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !summary.hasAstronomicalNight {
                Label("No dark observing window", systemImage: "moon.zzz")
                    .font(.subheadline)
                    .lineLimit(2)
            } else {
                Label(summary.primaryMessage, systemImage: "clock.badge.exclamationmark")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showDominantCondition, summary.bestWindow != nil {
                Text(summary.primaryMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var timeZone: TimeZone? {
        summary.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
    }

    private var density: WidgetContentDensity {
        WidgetContentDensity.resolve(for: dynamicTypeSize)
    }

    private var conditionSummary: SmallConditionSummary {
        WidgetTonightPresentation.smallConditionSummary(
            earlyQuality: summary.earlyQuality,
            lateQuality: summary.lateQuality,
            trend: summary.trend
        )
    }

    @ViewBuilder
    private func conditionSummaryRow(font: Font) -> some View {
        if let symbol = conditionSummary.symbol {
            Label {
                Text(conditionSummary.label)
            } icon: {
                Text(symbol)
            }
            .font(font)
            .lineLimit(1)
        } else {
            Text(conditionSummary.label)
                .font(font)
                .lineLimit(1)
        }
    }

    private var identityIcon: some View {
        Image(systemName: WidgetAppIdentity.symbol)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityHidden(WidgetAppIdentity.symbolIsDecorative)
    }

    private var scoreColor: Color {
        switch summary.observingQualityScore {
        case 80...100: return .green
        case 60..<80: return .blue
        case 40..<60: return .orange
        default: return .red
        }
    }
}

#Preview("Small · Extra Small") {
    NightConditionsWidgetSmallEntryView(summary: NightConditionsEntry.smallHeaderPreviewSummary)
        .environment(\.dynamicTypeSize, .xSmall)
}

#Preview("Small · Default") {
    NightConditionsWidgetSmallEntryView(summary: NightConditionsEntry.smallHeaderPreviewSummary)
        .environment(\.dynamicTypeSize, .large)
}

#Preview("Small · Extra Large") {
    NightConditionsWidgetSmallEntryView(summary: NightConditionsEntry.smallHeaderPreviewSummary)
        .environment(\.dynamicTypeSize, .xLarge)
}

#Preview("Small · Extra Extra Large · Compact") {
    NightConditionsWidgetSmallEntryView(summary: NightConditionsEntry.smallHeaderPreviewSummary)
        .environment(\.dynamicTypeSize, .xxLarge)
}

#Preview("Small · Accessibility 2 · Compact") {
    NightConditionsWidgetSmallEntryView(summary: NightConditionsEntry.smallHeaderPreviewSummary)
        .environment(\.dynamicTypeSize, .accessibility2)
}

#Preview("Small · Accessibility 5 · Minimal") {
    NightConditionsWidgetSmallEntryView(summary: NightConditionsEntry.smallHeaderPreviewSummary)
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Small · Accessibility 3 · Minimal") {
    NightConditionsWidgetSmallEntryView(summary: NightConditionsEntry.smallHeaderPreviewSummary)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Small · Accessibility 5 · Excellent") {
    NightConditionsWidgetSmallEntryView(summary: NightConditionsEntry.smallHeaderExcellentPreviewSummary)
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Small · Different Halves") {
    NightConditionsWidgetSmallEntryView(summary: NightConditionsEntry.layoutPreviewSummary)
        .environment(\.dynamicTypeSize, .xxLarge)
}

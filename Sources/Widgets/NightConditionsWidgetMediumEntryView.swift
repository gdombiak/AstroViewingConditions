import SharedCode
import SwiftUI
import WidgetKit

struct NightConditionsWidgetMediumEntryView: View {
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
            content(factorLimit: 3, showDominantCondition: true)
            content(factorLimit: 3, showDominantCondition: false)
            content(factorLimit: 2, showDominantCondition: false)
        }
    }

    private var compactContent: some View {
        fittingCondensedContent(for: .compact)
    }

    private var minimalContent: some View {
        fittingCondensedContent(for: .minimal)
    }

    private func fittingCondensedContent(for density: WidgetContentDensity) -> some View {
        ViewThatFits(in: .vertical) {
            condensedCandidate(density: density, includesEarlyLate: true, factorLayout: .columns)
            condensedCandidate(density: density, includesEarlyLate: true, factorLayout: .summary)
            condensedCandidate(density: density, includesEarlyLate: true, factorLayout: .none)
            condensedCandidate(density: density, includesEarlyLate: false, factorLayout: .none)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func condensedCandidate(
        density: WidgetContentDensity,
        includesEarlyLate: Bool,
        factorLayout: CondensedFactorLayout
    ) -> some View {
        VStack(alignment: .leading, spacing: density == .minimal ? 3 : 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(spacing: 3) {
                    identityIcon
                    Text("Tonight")
                        .font((density == .minimal ? Font.caption2 : .caption).weight(.semibold))
                }
                Spacer(minLength: 4)
                Text("\(summary.score)")
                    .font(.system(density == .minimal ? .title3 : .title2, design: .rounded).weight(.bold))
                    .foregroundStyle(scoreColor)
                Text(summary.verdict)
                    .font((density == .minimal ? Font.caption2 : .caption).weight(.semibold))
                    .foregroundStyle(scoreColor)
                    .lineLimit(1)
            }

            if includesEarlyLate {
                Text("Early \(summary.earlyQuality)  \(WidgetTonightPresentation.trendSymbol(for: summary.trend))  Late \(summary.lateQuality)")
                    .font((density == .minimal ? Font.caption2 : .caption).weight(.medium))
                    .lineLimit(2)
            }

            if let bestWindow = WidgetTonightPresentation.compactBestWindowText(summary.bestWindow, timeZone: timeZone) {
                Text("Best \(bestWindow)")
                    .font(density == .minimal ? .caption2 : .caption)
                    .lineLimit(2)
            } else if !summary.hasAstronomicalNight {
                Label("No dark observing window", systemImage: "moon.zzz")
                    .font(density == .minimal ? .caption2 : .caption)
                    .lineLimit(2)
            } else {
                Text(summary.primaryMessage)
                    .font(density == .minimal ? .caption2 : .caption)
                    .lineLimit(2)
            }

            switch factorLayout {
            case .columns:
                HStack(alignment: .top, spacing: 10) {
                    ForEach(
                        WidgetTonightPresentation.mediumLayoutFactors(
                            summary.factors,
                            density: density,
                            includesFactors: true
                        ),
                        id: \.label
                    ) { factor in
                        FactorValueView(factor: factor, compact: true, condensed: density == .minimal)
                    }
                }
            case .summary:
                condensedFactorSummary(density: density)
            case .none:
                EmptyView()
            }
        }
    }

    private func content(factorLimit: Int, showDominantCondition: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        identityIcon
                        Text("Tonight at a Glance")
                            .font(.caption.weight(.semibold))
                    }
                    if WidgetTonightPresentation.mediumLayoutShowsLocation(for: density) {
                        Text(summary.locationName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(summary.score)")
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .foregroundStyle(scoreColor)
                    Text(summary.verdict)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(scoreColor)
                        .lineLimit(1)
                }
            }

            Text("Early \(summary.earlyQuality)  \(WidgetTonightPresentation.trendSymbol(for: summary.trend))  Late \(summary.lateQuality)")
                .font(.subheadline.weight(.medium))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)

            if let bestWindow = WidgetTonightPresentation.bestWindowText(summary.bestWindow, timeZone: timeZone) {
                Label("Best window  \(bestWindow)", systemImage: "clock")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !summary.hasAstronomicalNight {
                Label("No dark observing window", systemImage: "moon.zzz")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label(summary.primaryMessage, systemImage: "clock.badge.exclamationmark")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            factorContent(limit: factorLimit)

            if showDominantCondition, summary.bestWindow != nil {
                Text(summary.primaryMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func factorContent(limit: Int) -> some View {
        let factors = Array(summary.factors.prefix(limit))
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(factors, id: \.label) { factor in
                    FactorValueView(factor: factor, compact: false)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                ForEach(factors, id: \.label) { factor in
                    FactorValueView(factor: factor, compact: true)
                }
            }
        }
    }

    private var timeZone: TimeZone? {
        summary.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
    }

    private var density: WidgetContentDensity {
        WidgetContentDensity.resolve(for: dynamicTypeSize)
    }

    @ViewBuilder
    private func condensedFactorSummary(density: WidgetContentDensity) -> some View {
        let factors = WidgetTonightPresentation.mediumLayoutFactors(summary.factors, density: density)
        if !factors.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(factors.enumerated()), id: \.element.label) { index, factor in
                        if index > 0 {
                            Text("  •  ")
                                .foregroundStyle(.secondary)
                        }
                        Text(factor.label)
                            .foregroundStyle(.secondary)
                        Text(" \(factor.value)")
                            .foregroundStyle(factorToneColor(factor.tone))
                    }
                }
                .font(density == .minimal ? .caption2 : .caption)
                    .fixedSize(horizontal: true, vertical: false)
                EmptyView()
            }
        }
    }

    private func factorToneColor(_ tone: NightQualityDisplayFactor.Tone) -> Color {
        switch tone {
        case .favorable: return .green
        case .neutral: return .orange
        case .limiting: return .red
        }
    }

    private var identityIcon: some View {
        Image(systemName: WidgetTonightPresentation.identitySymbol)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityHidden(WidgetTonightPresentation.identitySymbolIsDecorative)
    }

    private var scoreColor: Color {
        switch summary.score {
        case 80...100: return .green
        case 60..<80: return .blue
        case 40..<60: return .orange
        default: return .red
        }
    }
}

private enum CondensedFactorLayout {
    case columns
    case summary
    case none
}

#Preview("Medium · Extra Small") {
    NightConditionsWidgetMediumEntryView(summary: NightConditionsEntry.layoutPreviewSummary)
        .environment(\.dynamicTypeSize, .xSmall)
}

#Preview("Medium · Default") {
    NightConditionsWidgetMediumEntryView(summary: NightConditionsEntry.layoutPreviewSummary)
        .environment(\.dynamicTypeSize, .large)
}

#Preview("Medium · Extra Extra Large · Compact") {
    NightConditionsWidgetMediumEntryView(summary: NightConditionsEntry.layoutPreviewSummary)
        .environment(\.dynamicTypeSize, .xxLarge)
}

#Preview("Medium · Accessibility 2 · Compact") {
    NightConditionsWidgetMediumEntryView(summary: NightConditionsEntry.layoutPreviewSummary)
        .environment(\.dynamicTypeSize, .accessibility2)
}

#Preview("Medium · Accessibility 5 · Minimal") {
    NightConditionsWidgetMediumEntryView(summary: NightConditionsEntry.layoutPreviewSummary)
        .environment(\.dynamicTypeSize, .accessibility5)
}

struct FactorValueView: View {
    let factor: NightQualityDisplayFactor
    let compact: Bool
    let condensed: Bool

    init(factor: NightQualityDisplayFactor, compact: Bool, condensed: Bool = false) {
        self.factor = factor
        self.compact = compact
        self.condensed = condensed
    }

    var body: some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: 1) {
                    Text(factor.label)
                        .font(condensed ? .caption2 : .caption)
                        .foregroundStyle(.secondary)
                    Text(factor.value)
                        .font((condensed ? Font.caption2 : .caption).weight(.semibold))
                        .foregroundStyle(color)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("\(factor.label) \(factor.value)")
                    .font((condensed ? Font.caption2 : .caption).weight(.semibold))
                    .foregroundStyle(color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var color: Color {
        switch factor.tone {
        case .favorable: return .green
        case .neutral: return .orange
        case .limiting: return .red
        }
    }
}

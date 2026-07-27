import SharedCode
import SwiftUI

private enum OutlookRowStyle { case regular, compact, minimal }

struct ThreeNightOutlookWidgetMediumEntryView: View {
    let summary: WidgetThreeNightOutlookSummary
    let dataStatus: WidgetDataStatus?
    let referenceDate: Date
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        summary: WidgetThreeNightOutlookSummary,
        dataStatus: WidgetDataStatus? = nil,
        referenceDate: Date = Date()
    ) {
        self.summary = summary
        self.dataStatus = dataStatus
        self.referenceDate = referenceDate
    }

    private var timeZone: TimeZone? {
        summary.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
    }

    var body: some View {
        Group {
            switch ThreeNightOutlookLayoutPolicy.mode(for: dynamicTypeSize) {
            case .standardWithLocationPreference:
                standardCandidates()
            case .largestStandard:
                largestStandardCandidates()
            case .accessibility:
                accessibilityCandidates()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func standardCandidates() -> some View {
        ViewThatFits(in: .vertical) {
            content(
                style: .regular,
                showsLocation: true,
                showsVerdict: true,
                showsSymbol: true
            )
            content(style: .compact, showsLocation: true, showsVerdict: true, showsSymbol: true)
            content(style: .compact, showsLocation: false, showsVerdict: true, showsSymbol: true)
            content(style: .minimal, showsLocation: false, showsVerdict: false, showsSymbol: true)
        }
    }

    private func largestStandardCandidates() -> some View {
        ViewThatFits(in: .vertical) {
            content(style: .compact, showsLocation: false, showsVerdict: false, showsSymbol: true)
            content(style: .minimal, showsLocation: false, showsVerdict: false, showsSymbol: true)
        }
    }

    private func accessibilityCandidates() -> some View {
        ViewThatFits(in: .vertical) {
            content(style: .minimal, showsLocation: false, showsVerdict: false, showsSymbol: true)
        }
    }

    private func content(
        style: OutlookRowStyle, showsLocation: Bool, showsVerdict: Bool, showsSymbol: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: style == .regular ? 5 : 3) {
            header(style: style, showsLocation: showsLocation, showsSymbol: showsSymbol)
            ForEach(Array(summary.nights.enumerated()), id: \.element.id) { index, night in
                if index > 0 { Divider() }
                row(night, style: style, showsVerdict: showsVerdict)
            }
            dataAsOfFooter
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func header(style: OutlookRowStyle, showsLocation: Bool, showsSymbol: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if showsSymbol {
                Image(systemName: WidgetAppIdentity.symbol)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            Text(style == .minimal ? "3-Night Outlook" : "Three-Night Outlook")
                .font((style == .regular ? Font.subheadline : .caption).weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if showsLocation {
                Text(summary.locationName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(
        _ night: WidgetThreeNightOutlookNight, style: OutlookRowStyle, showsVerdict: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(night.displayLabel)
                    .font(style == .regular ? .subheadline : .caption)
                    .fontWeight(.semibold)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 3)
                if let score = night.score {
                    Text("\(score)")
                        .font((style == .regular ? Font.subheadline : .caption).weight(.bold))
                        .foregroundStyle(scoreColor(night.scoreTone))
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityLabel("Score \(score) out of 100")
                } else {
                    Text("—").font(.caption).accessibilityLabel("Score unavailable")
                }
                if showsVerdict {
                    Text(night.verdict)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if night.isBestNight {
                    Text("Best")
                        .font(.caption2.weight(.semibold))
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityLabel("Best night")
                }
            }
            Text(WidgetThreeNightOutlookPresentation.windowText(
                for: night, timeZone: timeZone, compact: style != .regular
            ))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func scoreColor(_ tone: WidgetTargetScoreTone?) -> Color {
        switch tone {
        case .positive: .green
        case .informational: .blue
        case .caution: .orange
        case .negative: .red
        case nil: .secondary
        }
    }

    @ViewBuilder
    private var dataAsOfFooter: some View {
        if let dataStatus {
            WidgetDataAsOfStatusView(status: dataStatus, referenceDate: referenceDate)
        }
    }
}

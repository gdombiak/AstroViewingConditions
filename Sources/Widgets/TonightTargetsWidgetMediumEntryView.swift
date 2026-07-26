import SharedCode
import SwiftUI

private enum TargetRowStyle {
    case regular
    case reducedCompact
    case minimal
}

struct TonightTargetsWidgetMediumEntryView: View {
    let summary: WidgetTonightTargetsSummary

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            switch density {
            case .regular:
                ViewThatFits(in: .vertical) {
                    content(
                        targetCount: 3,
                        showsHeader: true,
                        showsLocation: true,
                        includesCategory: true,
                        includesPosition: true,
                        showsSymbol: true,
                        showsScore: true,
                        showsBestTime: true,
                        rowStyle: .regular
                    )
                    content(
                        targetCount: 2,
                        showsHeader: true,
                        showsLocation: true,
                        includesCategory: true,
                        includesPosition: true,
                        showsSymbol: true,
                        showsScore: true,
                        showsBestTime: true,
                        rowStyle: .regular
                    )
                    content(
                        targetCount: 2,
                        showsHeader: true,
                        showsLocation: false,
                        includesCategory: false,
                        includesPosition: false,
                        showsSymbol: true,
                        showsScore: true,
                        showsBestTime: true,
                        rowStyle: .regular
                    )
                }
            case .compact:
                ViewThatFits(in: .vertical) {
                    content(
                        targetCount: 2,
                        showsHeader: true,
                        showsLocation: false,
                        includesCategory: false,
                        includesPosition: true,
                        showsSymbol: true,
                        showsScore: true,
                        showsBestTime: true,
                        rowStyle: .regular
                    )
                    reducedIdentityCandidate(
                        targetCount: 2,
                        showsScore: true,
                        showsBestTime: true,
                        rowStyle: .reducedCompact
                    )
                    reducedIdentityCandidate(
                        targetCount: 1,
                        showsScore: true,
                        showsBestTime: true,
                        rowStyle: .reducedCompact
                    )
                    reducedIdentityCandidate(
                        targetCount: 1,
                        showsScore: true,
                        showsBestTime: false,
                        rowStyle: .reducedCompact
                    )
                    reducedIdentityCandidate(
                        targetCount: 1,
                        showsScore: false,
                        showsBestTime: false,
                        rowStyle: .reducedCompact
                    )
                }
            case .minimal:
                ViewThatFits(in: .vertical) {
                    reducedIdentityCandidate(
                        targetCount: 1,
                        showsScore: true,
                        showsBestTime: true,
                        rowStyle: .minimal
                    )
                    reducedIdentityCandidate(
                        targetCount: 1,
                        showsScore: true,
                        showsBestTime: false,
                        rowStyle: .minimal
                    )
                    reducedIdentityCandidate(
                        targetCount: 1,
                        showsScore: false,
                        showsBestTime: false,
                        rowStyle: .minimal
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func reducedIdentityCandidate(
        targetCount: Int,
        showsScore: Bool,
        showsBestTime: Bool,
        rowStyle: TargetRowStyle
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: WidgetAppIdentity.symbol)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                reducedIdentityLabel(for: rowStyle)
            }

            content(
                targetCount: targetCount,
                showsHeader: false,
                showsLocation: false,
                includesCategory: false,
                includesPosition: false,
                showsScore: showsScore,
                showsBestTime: showsBestTime,
                rowStyle: rowStyle
            )
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func reducedIdentityLabel(
        for rowStyle: TargetRowStyle
    ) -> some View {
        switch rowStyle {
        case .regular, .reducedCompact:
            Text("Tonight’s Targets")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
        case .minimal:
            Text("Tonight")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func content(
        targetCount: Int,
        showsHeader: Bool,
        showsLocation: Bool,
        includesCategory: Bool,
        includesPosition: Bool,
        showsSymbol: Bool = false,
        showsScore: Bool,
        showsBestTime: Bool,
        rowStyle: TargetRowStyle
    ) -> some View {
        let targets = Array(summary.targets.prefix(targetCount))

        return VStack(alignment: .leading, spacing: contentSpacing(for: rowStyle)) {
            if showsHeader {
                header(showsLocation: showsLocation, showsSymbol: showsSymbol)
            }

            ForEach(Array(targets.enumerated()), id: \.element.targetID) { index, target in
                if index > 0 {
                    Divider()
                }
                targetRow(
                    target,
                    includesCategory: includesCategory,
                    includesPosition: includesPosition,
                    showsScore: showsScore,
                    showsBestTime: showsBestTime,
                    rowStyle: rowStyle
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func header(showsLocation: Bool, showsSymbol: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if showsSymbol {
                Image(systemName: WidgetAppIdentity.symbol)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("Tonight’s Targets")
                    .font((density == .minimal ? Font.caption : .subheadline).weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if showsLocation {
                    Text(summary.locationName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func targetRow(
        _ target: WidgetTonightTargetSummary,
        includesCategory: Bool,
        includesPosition: Bool,
        showsScore: Bool,
        showsBestTime: Bool,
        rowStyle: TargetRowStyle
    ) -> some View {
        VStack(alignment: .leading, spacing: targetRowSpacing(for: rowStyle)) {
            if showsScore {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    targetName(target, rowStyle: rowStyle)

                    Spacer(minLength: 4)

                    Text("\(target.score)")
                        .font(scoreFont(for: rowStyle))
                        .foregroundStyle(scoreColor(target.scoreTone))
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityLabel("Score \(target.score) out of 100")
                }
            } else {
                targetName(target, rowStyle: rowStyle)
            }

            if showsBestTime || rowStyle != .minimal {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if showsBestTime,
                       let bestTime = WidgetTonightTargetsPresentation.bestTimeText(
                        target.bestTime,
                        timeZone: timeZone
                       ) {
                        Text("Best \(bestTime)")
                            .font(bestTimeFont(for: rowStyle))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if rowStyle != .minimal,
                       let metadata = WidgetTonightTargetsPresentation.secondaryMetadata(
                        for: target,
                        includesCategory: includesCategory,
                        includesPosition: includesPosition
                       ) {
                        Text(metadata)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func targetName(
        _ target: WidgetTonightTargetSummary,
        rowStyle: TargetRowStyle
    ) -> some View {
        Text(target.displayName)
            .font(targetNameFont(for: rowStyle))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func contentSpacing(for rowStyle: TargetRowStyle) -> CGFloat {
        switch rowStyle {
        case .regular:
            return 7
        case .reducedCompact:
            return 4
        case .minimal:
            return 5
        }
    }

    private func targetRowSpacing(for rowStyle: TargetRowStyle) -> CGFloat {
        switch rowStyle {
        case .regular:
            return density == .regular ? 2 : 1
        case .reducedCompact:
            return 1
        case .minimal:
            return 1
        }
    }

    private func targetNameFont(for rowStyle: TargetRowStyle) -> Font {
        switch rowStyle {
        case .regular:
            return .subheadline.weight(.semibold)
        case .reducedCompact:
            return .caption.weight(.semibold)
        case .minimal:
            return .caption2.weight(.semibold)
        }
    }

    private func scoreFont(for rowStyle: TargetRowStyle) -> Font {
        switch rowStyle {
        case .regular:
            return .subheadline.weight(.bold)
        case .reducedCompact:
            return .caption.weight(.bold)
        case .minimal:
            return .caption2.weight(.bold)
        }
    }

    private func bestTimeFont(for rowStyle: TargetRowStyle) -> Font {
        switch rowStyle {
        case .regular:
            return .caption
        case .reducedCompact, .minimal:
            return .caption2
        }
    }

    private var density: WidgetContentDensity {
        WidgetContentDensity.resolve(for: dynamicTypeSize)
    }

    private var timeZone: TimeZone? {
        summary.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
    }

    private func scoreColor(_ tone: WidgetTargetScoreTone) -> Color {
        switch tone {
        case .positive:
            return .green
        case .informational:
            return .blue
        case .caution:
            return .orange
        case .negative:
            return .red
        }
    }
}

#Preview("Targets · Default") {
    TonightTargetsWidgetMediumEntryView(summary: .preview)
        .environment(\.dynamicTypeSize, .large)
}

#Preview("Targets · Extra Large") {
    TonightTargetsWidgetMediumEntryView(summary: .preview)
        .environment(\.dynamicTypeSize, .xLarge)
}

#Preview("Targets · Extra Extra Large") {
    TonightTargetsWidgetMediumEntryView(summary: .preview)
        .environment(\.dynamicTypeSize, .xxLarge)
}

#Preview("Targets · Extra Extra Extra Large") {
    TonightTargetsWidgetMediumEntryView(summary: .preview)
        .environment(\.dynamicTypeSize, .xxxLarge)
}

#Preview("Targets · Accessibility 1") {
    TonightTargetsWidgetMediumEntryView(summary: .preview)
        .environment(\.dynamicTypeSize, .accessibility1)
}

#Preview("Targets · Accessibility 2") {
    TonightTargetsWidgetMediumEntryView(summary: .preview)
        .environment(\.dynamicTypeSize, .accessibility2)
}

#Preview("Targets · Accessibility 3") {
    TonightTargetsWidgetMediumEntryView(summary: .preview)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Targets · Accessibility 5") {
    TonightTargetsWidgetMediumEntryView(summary: .preview)
        .environment(\.dynamicTypeSize, .accessibility5)
}

import SharedCode
import SwiftUI

struct CurrentConditionsCard: View {
    let forecast: HourlyForecast?
    let unitConverter: AstroUnitConverter
    let timeZone: TimeZone?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appPalette) private var palette
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Current Conditions", systemImage: "eye.fill")
                    .font(.headline)
                Spacer()
                if let time = forecast?.time {
                    Text(DateFormatters.formatTime(time, in: timeZone))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            
            if let forecast = forecast {
                metricsView(for: forecast)
                supportingMetricsView(for: forecast)
                .padding(.top, 4)
            } else {
                Text("No data available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
        .dashboardCardStyle()
    }
    
    // Keep very high cloud cover visible against the shared card background in light mode.
    private func cloudIconColor(for percentage: Int) -> Color {
        if palette.appearance == .field { return palette.accent }
        if colorScheme == .light && percentage > 90 {
            return Color(uiColor: .systemGray)
        }
        return ConditionColorPalette.astronomyRiskBackground(for: percentage)
    }

    // Fog background: same gradient as clouds
    private func fogBackgroundColor(for percentage: Int) -> Color {
        if palette.appearance == .field { return palette.subduedFill }
        return ConditionColorPalette.astronomyRiskBackground(for: percentage)
    }
    
    private func fogTextColor(for percentage: Int) -> Color {
        if palette.appearance == .field { return palette.primaryText }
        return ConditionColorPalette.astronomyRiskText(for: percentage)
    }

    // Visibility color: green for good (>10km), yellow for moderate (5-10km), orange/red for poor
    private func visibilityColor(for meters: Double) -> Color {
        switch meters {
        case 0..<1000:
            return palette.statusColor(.negative)
        case 1000..<5000:
            return palette.statusColor(.caution)
        case 5000..<10000:
            return palette.statusColor(.informational)
        default:
            return palette.statusColor(.positive)
        }
    }

    private var usesExpandedMetricsLayout: Bool {
        dynamicTypeSize.requiresExpandedCompactLayout
            && horizontalSizeClass != .regular
    }

    @ViewBuilder
    private func metricsView(for forecast: HourlyForecast) -> some View {
        if usesExpandedMetricsLayout {
            LazyVGrid(
                columns: metricColumns,
                alignment: .leading,
                spacing: 16
            ) {
                ForEach(CurrentConditionMetric.allCases) { metric in
                    conditionItem(for: metric, forecast: forecast, isExpanded: true)
                }
            }
        } else {
            HStack(spacing: 16) {
                ForEach(CurrentConditionMetric.allCases) { metric in
                    conditionItem(for: metric, forecast: forecast, isExpanded: false)
                }
            }
        }
    }

    private var metricColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible(), spacing: 16)]
        }
        return [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
    }

    private func conditionItem(
        for metric: CurrentConditionMetric,
        forecast: HourlyForecast,
        isExpanded: Bool
    ) -> some View {
        switch metric {
        case .cloud:
            ConditionItem(
                icon: "cloud.fill",
                iconColor: cloudIconColor(for: forecast.cloudCover),
                value: "\(forecast.cloudCover)%",
                label: "Cloud",
                isExpanded: isExpanded
            )
        case .temperature:
            ConditionItem(
                icon: "thermometer",
                iconColor: .orange,
                value: unitConverter.formatTemperature(forecast.temperature),
                label: "Temp",
                isExpanded: isExpanded
            )
        case .humidity:
            ConditionItem(
                icon: "humidity.fill",
                iconColor: .blue,
                value: "\(forecast.humidity)%",
                label: "Humidity",
                isExpanded: isExpanded
            )
        case .wind:
            ConditionItem(
                icon: "wind",
                iconColor: .gray,
                value: unitConverter.formatWindSpeed(forecast.windSpeed),
                label: "Wind",
                isExpanded: isExpanded
            )
        }
    }

    @ViewBuilder
    private func supportingMetricsView(for forecast: HourlyForecast) -> some View {
        let fogScore = FogCalculator.calculate(from: forecast)

        if usesExpandedMetricsLayout {
            VStack(alignment: .leading, spacing: 10) {
                if let visibility = forecast.visibility {
                    visibilityView(visibility)
                }
                if fogScore.score > 0 {
                    fogView(score: fogScore.score)
                }
            }
        } else {
            HStack(spacing: 20) {
                if let visibility = forecast.visibility {
                    visibilityView(visibility)
                }
                if fogScore.score > 0 {
                    fogView(score: fogScore.score)
                }
                Spacer()
            }
        }
    }

    private func visibilityView(_ visibility: Double) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "eye")
                .foregroundStyle(.secondary)
            Text("Visibility:")
                .font(.subheadline)
                .fixedSize(horizontal: true, vertical: false)
            Text(unitConverter.formatVisibility(visibility))
                .font(.subheadline)
                .foregroundStyle(visibilityColor(for: visibility))
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func fogView(score: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "cloud.fog.fill")
                .font(.footnote)
                .foregroundStyle(fogTextColor(for: score))
            Text("\(score)%")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(fogTextColor(for: score))
        }
        .frame(minWidth: 60, minHeight: 28)
        .background(fogBackgroundColor(for: score))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private enum CurrentConditionMetric: CaseIterable, Identifiable {
    case cloud
    case temperature
    case humidity
    case wind

    var id: Self { self }
}

struct ConditionItem: View {
    @Environment(\.appPalette) private var palette
    let icon: String
    let iconColor: Color
    let value: String
    let label: String
    let isExpanded: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(palette.appearance == .field ? palette.accent : iconColor)
            Text(value)
                .font(.body)
                .fontWeight(.semibold)
                .fixedSize(horizontal: isExpanded, vertical: false)
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: isExpanded, vertical: false)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    CurrentConditionsCard(
        forecast: HourlyForecast(
            time: Date(),
            cloudCover: 25,
            humidity: 65,
            windSpeed: 12.5,
            windDirection: 180,
            temperature: 15.5,
            dewPoint: 10.0,
            visibility: 10000,
            lowCloudCover: 20
        ),
        unitConverter: AstroUnitConverter(unitSystem: .metric),
        timeZone: nil
    )
    .padding()
}

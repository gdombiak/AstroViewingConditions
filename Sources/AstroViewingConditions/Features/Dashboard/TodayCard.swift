import SwiftUI

struct CurrentConditionsCard: View {
    let forecast: HourlyForecast?
    let unitConverter: UnitConverter
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Current Conditions", systemImage: "eye.fill")
                    .font(.headline)
                Spacer()
                if let time = forecast?.time {
                    Text(DateFormatters.formatTime(time))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if let forecast = forecast {
                HStack(spacing: 16) {
                    // Cloud Cover
                    ConditionItem(
                        icon: "cloud.fill",
                        iconColor: cloudColor(for: forecast.cloudCover),
                        value: "\(forecast.cloudCover)%",
                        label: "Cloud"
                    )
                    
                    // Temperature
                    ConditionItem(
                        icon: "thermometer",
                        iconColor: .orange,
                        value: unitConverter.formatTemperature(forecast.temperature),
                        label: "Temp"
                    )
                    
                    // Humidity
                    ConditionItem(
                        icon: "humidity.fill",
                        iconColor: .blue,
                        value: "\(forecast.humidity)%",
                        label: "Humidity"
                    )
                    
                    // Wind
                    ConditionItem(
                        icon: "wind",
                        iconColor: .gray,
                        value: unitConverter.formatWindSpeed(forecast.windSpeed),
                        label: "Wind"
                    )
                }
                
                // Visibility
                if let visibility = forecast.visibility {
                    HStack {
                        Image(systemName: "eye")
                            .foregroundStyle(.secondary)
                        Text("Visibility: \(unitConverter.formatVisibility(visibility))")
                            .font(.subheadline)
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            } else {
                Text("No data available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
        .padding()
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var cardBackground: some View {
        #if os(iOS)
        return Color(.systemGray6)
        #else
        return Color.gray.opacity(0.1)
        #endif
    }
    
    private func cloudColor(for percentage: Int) -> Color {
        switch percentage {
        case 0..<20:
            return .green
        case 20..<50:
            return .yellow
        case 50..<80:
            return .orange
        default:
            return .red
        }
    }
}

struct ConditionItem: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(iconColor)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
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
        unitConverter: UnitConverter(unitSystem: .metric)
    )
    .padding()
}

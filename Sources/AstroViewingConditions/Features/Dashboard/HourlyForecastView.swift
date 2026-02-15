import SwiftUI

struct HourlyForecastView: View {
    let forecasts: [HourlyForecast]
    let unitConverter: UnitConverter
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Hourly Forecast", systemImage: "clock")
                .font(.headline)
            
            if forecasts.isEmpty {
                Text("No forecast data available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(forecasts.prefix(24)) { forecast in
                            HourlyCell(forecast: forecast, unitConverter: unitConverter)
                        }
                    }
                    .padding(.horizontal, 4)
                }
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
}

struct HourlyCell: View {
    let forecast: HourlyForecast
    let unitConverter: UnitConverter
    
    private var isNow: Bool {
        Calendar.current.isDateInToday(forecast.time) &&
        Calendar.current.component(.hour, from: forecast.time) == Calendar.current.component(.hour, from: Date())
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Time
            Text(DateFormatters.formatTime(forecast.time))
                .font(.caption)
                .fontWeight(isNow ? .bold : .regular)
            
            // Cloud cover bar
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 30, height: 60)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(cloudColor)
                    .frame(width: 30, height: CGFloat(forecast.cloudCover) * 0.6)
            }
            
            // Cloud percentage
            Text("\(forecast.cloudCover)%")
                .font(.caption2)
                .fontWeight(.semibold)
            
            // Temperature
            Text(unitConverter.formatTemperature(forecast.temperature))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(isNow ? Color.accentColor.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var cloudColor: Color {
        switch forecast.cloudCover {
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

#Preview {
    let sampleForecasts = (0..<12).map { hour in
        HourlyForecast(
            time: Calendar.current.date(byAdding: .hour, value: hour, to: Date())!,
            cloudCover: Int.random(in: 0...100),
            humidity: 65,
            windSpeed: Double.random(in: 5...20),
            windDirection: 180,
            temperature: Double.random(in: 10...20),
            dewPoint: 10.0,
            visibility: 10000,
            lowCloudCover: 20
        )
    }
    
    HourlyForecastView(
        forecasts: sampleForecasts,
        unitConverter: UnitConverter(unitSystem: .metric)
    )
    .padding()
}

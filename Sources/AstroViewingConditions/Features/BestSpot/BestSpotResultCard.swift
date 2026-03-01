import SwiftUI

struct BestSpotResultCard: View {
    let locationScore: LocationScore
    let rank: Int
    let isSelected: Bool
    let onTap: () -> Void
    
    private var unitConverter: UnitConverter {
        UnitConverter(unitSystem: UserDefaults.standard.selectedUnitSystem)
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    // Rank badge
                    ZStack {
                        Circle()
                            .fill(rankBadgeColor)
                            .frame(width: 32, height: 32)
                        Text("\(rank)")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    }
                    
                    // Score badge
                    Text("\(locationScore.score)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(scoreColor)
                    
                    Text("/100")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    // Location info
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(locationScore.fullLocationString)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        if let elevation = locationScore.point.elevation {
                            Text("\(Int(elevation)) ft elevation")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // Summary
                Text(locationScore.summary)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                
                // Conditions breakdown
                HStack(spacing: 16) {
                    ConditionPill(
                        icon: "cloud.fill",
                        label: "Clouds",
                        value: "\(Int(locationScore.avgCloudCover))%",
                        color: cloudColor(locationScore.avgCloudCover)
                    )
                    
                    ConditionPill(
                        icon: "wind",
                        label: "Wind",
                        value: unitConverter.formatWindSpeed(locationScore.avgWindSpeed),
                        color: windColor(locationScore.avgWindSpeed)
                    )
                    
                    ConditionPill(
                        icon: "eye.fill",
                        label: "Fog",
                        value: "\(locationScore.fogScore.score)",
                        color: fogColor(locationScore.fogScore.score)
                    )
                }
            }
            .padding()
            .background(cardBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var rankBadgeColor: Color {
        switch rank {
        case 1: return .yellow
        case 2: return Color.gray.opacity(0.6)
        case 3: return Color.orange.opacity(0.7)
        default: return Color.gray.opacity(0.3)
        }
    }
    
    private var scoreColor: Color {
        let score = locationScore.score
        switch score {
        case 80...100: return .green
        case 60..<80: return .blue
        case 40..<60: return .orange
        default: return .red
        }
    }
    
    private func cloudColor(_ coverage: Double) -> Color {
        switch Int(coverage) {
        case 0..<20: return .green
        case 20..<50: return .blue
        case 50..<80: return .orange
        default: return .red
        }
    }
    
    private func windColor(_ speed: Double) -> Color {
        switch speed {
        case 0..<5: return .green
        case 5..<10: return .blue
        case 10..<15: return .orange
        default: return .red
        }
    }
    
    private func fogColor(_ score: Int) -> Color {
        switch score {
        case 0..<25: return .green
        case 25..<50: return .blue
        case 50..<75: return .orange
        default: return .red
        }
    }
    
    private var cardBackgroundColor: Color {
        #if os(iOS)
        return Color(uiColor: .systemGray6)
        #else
        return Color.gray.opacity(0.1)
        #endif
    }
}

struct ConditionPill: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        BestSpotResultCard(
            locationScore: LocationScore(
                point: GridPoint(
                    coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                    distanceMiles: 12.5,
                    bearing: 315,
                    elevation: 850
                ),
                score: 87,
                nightQuality: NightQualityAssessment(
                    rating: .excellent,
                    summary: "Perfect conditions for stargazing!",
                    details: NightQualityAssessment.Details(
                        cloudCoverScore: 5,
                        fogScoreAvg: 10,
                        moonIlluminationAvg: 5,
                        windSpeedAvg: 3.2
                    ),
                    bestWindow: nil,
                    hourlyRatings: [],
                    nightStart: Date(),
                    nightEnd: Date()
                ),
                fogScore: FogScore(score: 10, factors: []),
                avgCloudCover: 5,
                avgWindSpeed: 3.2,
                summary: "Crystal clear skies, calm winds"
            ),
            rank: 1,
            isSelected: true,
            onTap: {}
        )
        
        BestSpotResultCard(
            locationScore: LocationScore(
                point: GridPoint(
                    coordinate: Coordinate(latitude: 37.7849, longitude: -122.4094),
                    distanceMiles: 8.3,
                    bearing: 45,
                    elevation: nil
                ),
                score: 72,
                nightQuality: NightQualityAssessment(
                    rating: .good,
                    summary: "Good conditions overall",
                    details: NightQualityAssessment.Details(
                        cloudCoverScore: 25,
                        fogScoreAvg: 20,
                        moonIlluminationAvg: 15,
                        windSpeedAvg: 5.5
                    ),
                    bestWindow: nil,
                    hourlyRatings: [],
                    nightStart: Date(),
                    nightEnd: Date()
                ),
                fogScore: FogScore(score: 20, factors: []),
                avgCloudCover: 25,
                avgWindSpeed: 5.5,
                summary: "Mostly clear with light winds"
            ),
            rank: 2,
            isSelected: false,
            onTap: {}
        )
    }
    .padding()
}
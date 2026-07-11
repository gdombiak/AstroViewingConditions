import SharedCode
import SwiftUI

struct BestSpotResultCard: View {
    @Environment(\.appPalette) private var palette
    let locationScore: LocationScore
    let rank: Int
    let isSelected: Bool
    let onTap: () -> Void
    
    private var unitConverter: AstroUnitConverter {
        AstroUnitConverter(unitSystem: UnitSystemStorage.loadSelectedUnitSystem())
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
                            .foregroundStyle(palette.appearance == .field ? palette.primaryActionLabel : .white)
                    }
                    
                    // Score badge
                    Text("\(locationScore.score)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(TargetScoreColorProvider.color(for: locationScore.score, palette: palette))
                    
                    Text("/100")
                        .font(.caption)
                        .appTertiaryForeground()
                    
                    Spacer()
                    
                    // Location info
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(locationScore.fullLocationString)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text(locationScore.suitability.label)
                            .font(.caption2)
                            .appSecondaryForeground()
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
                        color: locationScore.nightQuality.cloudColor(locationScore.avgCloudCover)
                    )
                    
                    ConditionPill(
                        icon: "wind",
                        label: "Wind",
                        value: unitConverter.formatWindSpeed(locationScore.avgWindSpeed),
                        color: locationScore.nightQuality.windColor(locationScore.avgWindSpeed)
                    )
                    
                    ConditionPill(
                        icon: "eye.fill",
                        label: "Avg Fog",
                        value: "\(locationScore.fogScore.score)",
                        color: locationScore.nightQuality.fogColor(locationScore.fogScore.score)
                    )
                }

                HStack(spacing: 8) {
                    Text(locationScore.improvementSummary)
                    Spacer()
                    Text(locationScore.moonImpactSummary)
                }
                .font(.caption2)
                .appTertiaryForeground()
            }
            .padding()
            .background(cardBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected
                            ? (palette.appearance == .field ? palette.accent : .blue)
                            : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    private var rankBadgeColor: Color {
        if palette.appearance == .field {
            switch rank {
            case 1: return palette.statusColor(.caution)
            case 2: return palette.secondaryText.opacity(0.8)
            case 3: return palette.statusColor(.caution).opacity(0.65)
            default: return palette.subduedFill
            }
        }

        switch rank {
        case 1: return .yellow
        case 2: return Color.gray.opacity(0.6)
        case 3: return Color.orange.opacity(0.7)
        default: return Color.gray.opacity(0.3)
        }
    }
    
    private var cardBackgroundColor: Color {
        palette.elevatedBackground
    }
}

struct ConditionPill: View {
    @Environment(\.appPalette) private var palette
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(palette.appearance == .field ? color.opacity(0.62) : color)
            Text(label)
                .font(.caption2)
                .appSecondaryForeground()
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

import SwiftUI

struct FogScoreView: View {
    let fogScore: FogScore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Fog Risk", systemImage: "cloud.fog.fill")
                    .font(.headline)
                Spacer()
                Text("\(fogScore.percentage)%")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(fogColor)
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(fogColor)
                        .frame(width: geometry.size.width * CGFloat(fogScore.percentage) / 100, height: 8)
                }
            }
            .frame(height: 8)
            
            // Contributing factors
            if !fogScore.factors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Contributing factors:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    ForEach(fogScore.factors, id: \.self) { factor in
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(fogColor)
                            Text(factor.rawValue)
                                .font(.caption)
                            Spacer()
                        }
                    }
                }
            }
        }
        .padding()
        .background(fogColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var fogColor: Color {
        switch fogScore.percentage {
        case 0..<25:
            return .green
        case 25..<50:
            return .yellow
        case 50..<75:
            return .orange
        default:
            return .red
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        FogScoreView(fogScore: FogScore(percentage: 80, factors: [.highHumidity, .lowTempDewDiff]))
        FogScoreView(fogScore: FogScore(percentage: 30, factors: [.lowVisibility]))
    }
    .padding()
}

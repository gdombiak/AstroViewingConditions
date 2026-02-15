import SwiftUI

struct ISSCard: View {
    let passes: [ISSPass]
    
    private var upcomingPasses: [ISSPass] {
        passes.filter { $0.riseTime > Date() }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("ISS Passes", systemImage: "airplane")
                    .font(.headline)
                Spacer()
                if !upcomingPasses.isEmpty {
                    Text("\(upcomingPasses.count) upcoming")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if upcomingPasses.isEmpty {
                Text("No upcoming ISS passes in the next few days")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                VStack(spacing: 8) {
                    ForEach(upcomingPasses.prefix(5)) { pass in
                        ISSPassRow(pass: pass)
                        
                        if pass.id != upcomingPasses.prefix(5).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct ISSPassRow: View {
    let pass: ISSPass
    
    var body: some View {
        HStack {
            // Date and time
            VStack(alignment: .leading, spacing: 2) {
                Text(DateFormatters.formatShortDate(pass.riseTime))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(DateFormatters.formatTime(pass.riseTime))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Duration and elevation
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption)
                    Text(DateFormatters.formatDuration(pass.duration))
                        .font(.subheadline)
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.forward")
                        .font(.caption)
                    Text("\(Int(pass.maxElevation))° max")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    let samplePasses = [
        ISSPass(riseTime: Date().addingTimeInterval(3600), duration: 420, maxElevation: 65),
        ISSPass(riseTime: Date().addingTimeInterval(7200), duration: 380, maxElevation: 45),
        ISSPass(riseTime: Date().addingTimeInterval(86400), duration: 520, maxElevation: 82),
    ]
    
    ISSCard(passes: samplePasses)
        .padding()
}

import SharedCode
import SwiftUI

struct ISSCard: View {
    let passes: [ISSPass]
    let timeZone: TimeZone?
    let errorMessage: String?
    let title: String
    let emptyMessage: String
    
    private var upcomingPasses: [ISSPass] {
        Self.visiblePasses(passes, at: Date())
    }

    static func visiblePasses(_ passes: [ISSPass], at date: Date) -> [ISSPass] {
        passes
            .filter { $0.setTime > date }
            .sorted { $0.riseTime < $1.riseTime }
    }

    private var passCountDescription: String {
        let now = Date()
        let activeCount = upcomingPasses.filter { $0.riseTime <= now }.count
        let futureCount = upcomingPasses.count - activeCount
        if activeCount > 0 {
            return futureCount > 0
                ? "\(activeCount) active · \(futureCount) upcoming"
                : "\(activeCount) active"
        }
        return "\(futureCount) upcoming"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: "airplane")
                    .font(.headline)
                Spacer()
                if !upcomingPasses.isEmpty {
                    Text(passCountDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            } else if upcomingPasses.isEmpty {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                VStack(spacing: 8) {
                    ForEach(upcomingPasses.prefix(5)) { pass in
                        ISSPassRow(pass: pass, timeZone: timeZone)
                        
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
    let timeZone: TimeZone?
    
    var body: some View {
        HStack {
            // Date and time
            VStack(alignment: .leading, spacing: 2) {
                Text(DateFormatters.formatShortDate(pass.riseTime, in: timeZone))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(DateFormatters.formatTime(pass.riseTime, in: timeZone))
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
    
    ISSCard(
        passes: samplePasses,
        timeZone: nil,
        errorMessage: nil,
        title: "ISS Passes Tonight",
        emptyMessage: "No visible ISS passes tonight"
    )
        .padding()
}

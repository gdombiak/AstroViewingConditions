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

    nonisolated static func visiblePasses(_ passes: [ISSPass], at date: Date) -> [ISSPass] {
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
                        .font(.footnote)
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
        .dashboardCardStyle()
    }
}

struct ISSPassRow: View {
    let pass: ISSPass
    let timeZone: TimeZone?

    private var pathDescription: String? {
        guard let startDirection = pass.startDirection,
              let endDirection = pass.endDirection else { return nil }
        let start = pass.startElevation.map { "\(startDirection) \(Int($0))°" } ?? startDirection
        let end = pass.endElevation.map { "\(endDirection) \(Int($0))°" } ?? endDirection
        return "\(start) → \(end)"
    }

    private var peakDescription: String {
        let direction = pass.maxDirection.map { "\($0) " } ?? ""
        let peak = "\(direction)\(Int(pass.maxElevation))°"
        guard let maxTime = pass.maxTime else { return peak }
        return "\(peak) · \(DateFormatters.formatTime(maxTime, in: timeZone))"
    }

    private var timeColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(DateFormatters.formatTimeRange(
                from: pass.riseTime,
                to: pass.setTime,
                in: timeZone
            ))
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(DateFormatters.formatShortDate(pass.riseTime, in: timeZone))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func peakColumn(
        alignment: HorizontalAlignment,
        textAlignment: TextAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(peakDescription)
                .font(.subheadline)
                .fontWeight(.semibold)

            if let pathDescription {
                Text(pathDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(textAlignment)
    }
    
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                timeColumn
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 4)
                peakColumn(alignment: .trailing, textAlignment: .trailing)
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: 8) {
                timeColumn
                peakColumn(alignment: .leading, textAlignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        title: "ISS Passes",
        emptyMessage: "No visible ISS passes tonight"
    )
        .padding()
}

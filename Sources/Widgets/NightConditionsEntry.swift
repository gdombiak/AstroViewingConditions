import SharedCode
import WidgetKit
import Foundation

struct NightConditionsEntry: TimelineEntry, Sendable {
    let date: Date
    let assessment: NightQualityAssessment
    static var placeholder: NightConditionsEntry {
        NightConditionsEntry(
            date: Date(),
            assessment: NightQualityAssessment(
                rating: .good,
                summary: "Good conditions for stargazing tonight.",
                details: NightQualityAssessment.Details(
                    cloudCoverScore: 25,
                    fogScoreAvg: 15,
                    moonIlluminationAvg: 12,
                    windSpeedAvg: 2.5
                ),
                bestWindow: nil,
                hourlyRatings: [],
                nightStart: Date(),
                nightEnd: Date().addingTimeInterval(8 * 3600),
                trend: .stable,
                firstHalfScore: nil,
                secondHalfScore: nil
            )
        )
    }
}

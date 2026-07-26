import Foundation
import SharedCode
import SwiftUI

enum WidgetTonightTargetsPresentation {
    static func bestTimeText(
        _ bestTime: Date?,
        timeZone: TimeZone?
    ) -> String? {
        guard let bestTime else { return nil }
        return DateFormatters.formatTime(bestTime, in: timeZone)
            .replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    static func secondaryMetadata(
        for target: WidgetTonightTargetSummary,
        includesCategory: Bool,
        includesPosition: Bool
    ) -> String? {
        var values: [String] = []
        if includesCategory, !target.categoryLabel.isEmpty {
            values.append(target.categoryLabel)
        }
        if includesPosition, let positionLabel = target.positionLabel {
            values.append(positionLabel)
        }
        return values.isEmpty ? nil : values.joined(separator: "  •  ")
    }
}

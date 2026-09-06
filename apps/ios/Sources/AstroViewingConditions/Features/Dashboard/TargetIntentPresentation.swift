import SharedCode

enum TargetIntentPresentation {
    static func showsBadge(for intent: TargetObservingIntent) -> Bool {
        intent == .challenge
    }

    static func badgeText(for intent: TargetObservingIntent) -> String? {
        showsBadge(for: intent) ? "Challenge" : nil
    }

    static func detailGuidance(for intent: TargetObservingIntent) -> String? {
        nil
    }
}

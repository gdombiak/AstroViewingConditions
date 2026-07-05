import SharedCode

enum TargetIntentPresentation {
    static func showsBadge(for intent: TargetObservingIntent) -> Bool {
        intent == .challenge
    }

    static func badgeText(for intent: TargetObservingIntent) -> String? {
        showsBadge(for: intent) ? "Challenge" : nil
    }

    static func detailGuidance(for intent: TargetObservingIntent) -> String? {
        showsBadge(for: intent)
            ? "Challenge target: best from darker skies; low surface brightness may make it difficult from suburbs."
            : nil
    }
}

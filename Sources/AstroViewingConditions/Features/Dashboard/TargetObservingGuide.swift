struct TargetObservingGuide {
    enum WhyRecommendedOverride {
        case always(String)
        case withPlacement(String)
        case brightMoon(String)

        func text(hasBrightMoonImpact: Bool) -> String? {
            switch self {
            case .always(let text), .withPlacement(let text):
                return text
            case .brightMoon(let text):
                return hasBrightMoonImpact ? text : nil
            }
        }

        var appendsPlacement: Bool {
            if case .withPlacement = self { return true }
            return false
        }
    }

    let targetID: String
    let whyRecommendedOverride: WhyRecommendedOverride?
    let findingTips: String?
    let bestEquipment: String?
    let observingNotes: String?

    init(
        targetID: String,
        whyRecommendedOverride: WhyRecommendedOverride? = nil,
        findingTips: String? = nil,
        bestEquipment: String? = nil,
        observingNotes: String? = nil
    ) {
        self.targetID = targetID
        self.whyRecommendedOverride = whyRecommendedOverride
        self.findingTips = findingTips
        self.bestEquipment = bestEquipment
        self.observingNotes = observingNotes
    }
}

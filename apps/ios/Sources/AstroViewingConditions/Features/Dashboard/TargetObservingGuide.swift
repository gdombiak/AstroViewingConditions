struct TargetObservingGuide {
    let targetID: String
    let brightMoonContext: String?
    let findingTips: String?
    let bestEquipment: String?
    let observingNotes: String?

    init(
        targetID: String,
        brightMoonContext: String? = nil,
        findingTips: String? = nil,
        bestEquipment: String? = nil,
        observingNotes: String? = nil
    ) {
        self.targetID = targetID
        self.brightMoonContext = brightMoonContext
        self.findingTips = findingTips
        self.bestEquipment = bestEquipment
        self.observingNotes = observingNotes
    }
}

enum TargetDetailSectionKind: Equatable {
    case whyRecommended
    case findingTips
    case bestEquipment
    case observingNotes
}

struct TargetDetailContent: Equatable {
    struct Section: Equatable, Identifiable {
        let kind: TargetDetailSectionKind
        let title: String
        let text: String
        var id: String { title }
    }

    let name: String
    let displayType: String
    let score: Int
    let bestTime: String
    let compassDirectionLabel: String?
    let directionText: String?
    let altitudeDegrees: Double?
    let altitudeText: String?
    let azimuthDegrees: Double?
    let azimuthText: String?
    let imageAttribution: String?
    let sections: [Section]

    var direction: String? { directionText }
    var altitude: String? { altitudeText }

    func sections(hidingBestEquipment: Bool) -> [Section] {
        sections.filter { section in
            !hidingBestEquipment || section.kind != .bestEquipment
        }
    }

    var sectionsText: String {
        sections.map { "\($0.title) \($0.text)" }.joined(separator: " ")
    }

    var whyRecommended: String {
        sections.first(where: { $0.title == "Why recommended" })?.text ?? ""
    }
}

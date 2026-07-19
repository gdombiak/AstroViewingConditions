import Foundation
import SharedCode

struct TargetDetailContentBuilder {
    func build(
        from recommendation: TargetRecommendation,
        timeZone: TimeZone? = nil
    ) -> TargetDetailContent {
        let target = recommendation.target
        let guide = TargetObservingGuideCatalog.guide(for: target.id)
        let window = recommendation.visibilityWindow
        let windowText = DateFormatters.formatDashboardObservingTimeRange(
            from: window.start,
            to: window.end,
            in: timeZone
        )

        return TargetDetailContent(
            name: target.name,
            displayType: target.displayTypeName,
            score: recommendation.score,
            bestTime: windowText,
            compassDirectionLabel: window.direction,
            directionText: window.direction.map(Self.directionText),
            altitudeDegrees: window.maxAltitude,
            altitudeText: window.maxAltitude.map(Self.altitudeText),
            azimuthDegrees: window.azimuth,
            azimuthText: window.azimuth.map(Self.azimuthText),
            imageAttribution: target.image?.attributionText,
            sections: [
                .init(kind: .whyRecommended, title: "Why recommended", text: whyRecommended(recommendation, guide: guide)),
                .init(kind: .findingTips, title: "Finding tips", text: findingTips(for: target, guide: guide)),
                .init(kind: .bestEquipment, title: "Best equipment", text: equipment(for: target, guide: guide)),
                .init(kind: .observingNotes, title: "Observing notes", text: observingNotes(for: target, guide: guide))
            ]
        )
    }

    private func whyRecommended(
        _ recommendation: TargetRecommendation,
        guide: TargetObservingGuide?
    ) -> String {
        let target = recommendation.target
        let reasons = Set(recommendation.reasons)
        let summary = recommendation.summary
        let summaryLower = summary.lowercased()
        let hasBrightMoonImpact = reasons.contains(.moonInterference)
            || reasons.contains(.brightFullMoonDeepSkyImpact)
            || summaryLower.contains("bright moon")

        if let override = guide?.whyRecommendedOverride,
           let text = override.text(hasBrightMoonImpact: hasBrightMoonImpact) {
            return override.appendsPlacement
                ? Self.joinSentences(text, placementSentence(reasons: reasons))
                : text
        }

        if target.type == .moon, reasons.contains(.brightFullMoonDeepSkyImpact) {
            return "The bright full Moon is a good lunar target for this night, though it will make faint deep-sky objects harder to see."
        }

        if target.type == .planet, reasons.contains(.lowAltitude) {
            let obstruction = "This planet is visible, but it stays low in the sky, so trees, hills, or buildings may get in the way."
            if reasons.contains(.outsideAstronomicalDarkness) {
                return "\(obstruction) Its best window is in twilight rather than full darkness."
            }
            return obstruction
        }

        if hasBrightMoonImpact {
            switch target.deepSkyObjectType {
            case .doubleStar:
                return Self.joinSentences(
                    "This is a good target even under a bright Moon.",
                    placementSentence(reasons: reasons)
                )
            case .planetaryNebula:
                return "This small bright nebula is well placed during this observing window. The bright Moon may reduce contrast, but it should still be worth trying."
            case .globularCluster:
                return "This cluster is high in the sky during the best window. The bright Moon has a moderate impact, but it remains a useful telescope target."
            case .galaxy:
                return "This galaxy is well placed, but the bright Moon will wash out much of its detail."
            default:
                break
            }
        }

        var sentences: [String] = []
        if summaryLower != "visible tonight.",
           let summaryWithoutEquipmentAdvice = Self.recommendationSummaryWithoutEquipmentAdvice(summary) {
            sentences.append(Self.dateNeutralized(summaryWithoutEquipmentAdvice))
        }
        if let placement = placementSentence(reasons: reasons),
           !sentences.contains(where: { Self.overlapsPlacement($0, placement) }) {
            sentences.append(placement)
        }
        if sentences.isEmpty {
            sentences.append("This target should be worth observing during its best window.")
        }
        return sentences.prefix(3).joined(separator: " ")
    }

    private func placementSentence(reasons: Set<TargetRecommendationReason>) -> String? {
        let isHigh = reasons.contains(.highAltitude)
        let isDark = reasons.contains(.astronomicalDarkness)
        let goodWeather = reasons.contains(.goodNightQuality)
        let poorWeather = reasons.contains(.poorWeather)

        var clause: String?
        if isHigh && isDark {
            clause = "It will be high in the sky during astronomical darkness"
        } else if isHigh {
            clause = "It will be high in the sky during the best window"
        } else if isDark {
            clause = "It will be visible during astronomical darkness"
        }

        if goodWeather {
            return clause.map { "\($0), and the weather looks favorable." }
                ?? "The weather looks favorable during the best window."
        }
        if poorWeather {
            return clause.map { "\($0), though clouds or haze may interfere." }
                ?? "Clouds or haze may make it harder to see."
        }
        return clause.map { "\($0)." }
    }

    private func findingTips(
        for target: ObservableTarget,
        guide: TargetObservingGuide?
    ) -> String {
        if let findingTips = guide?.findingTips { return findingTips }

        switch (target.type, target.deepSkyObjectType) {
        case (.moon, _):
            return "Trace the terminator, where long shadows make craters and ridges easier to recognize."
        case (.planet, _):
            return "Wait for brief moments of steady seeing, when fine detail may become easier to distinguish."
        case (.deepSky, .openCluster):
            return "Scan slowly around the target and look for the distinctive pattern formed by its brighter members."
        case (.deepSky, .globularCluster):
            return "Use averted vision on the outer halo, then increase magnification gradually to compare the compact core with the surrounding granularity."
        case (.deepSky, .planetaryNebula):
            return "Compare direct and averted vision and look for a compact disk that remains slightly extended beside nearby stars."
        case (.deepSky, .galaxy):
            return "Find the brighter central glow first, then use averted vision to trace the galaxy’s orientation and fainter extent."
        case (.deepSky, .doubleStar):
            return "Wait for steady seeing, then increase magnification gradually until the pair separates cleanly."
        case (.deepSky, .diffuseNebula):
            return "Shield your eyes from stray light and sweep slowly across the field to make faint boundaries easier to notice."
        default:
            return "Allow your eyes time to adapt, then scan slowly around the target and compare nearby stars or patterns."
        }
    }

    private func equipment(
        for target: ObservableTarget,
        guide: TargetObservingGuide?
    ) -> String {
        if let bestEquipment = guide?.bestEquipment { return bestEquipment }

        switch (target.type, target.deepSkyObjectType) {
        case (.moon, _):
            return "Use the naked eye, binoculars, or a telescope. A Moon filter can reduce brightness and improve comfort."
        case (.planet, _):
            return "Use the naked eye to locate it, then a telescope for detail."
        case (.deepSky, .doubleStar):
            return "For this double star, use a telescope with medium or high magnification to separate the stars."
        case (.deepSky, .globularCluster):
            return "A telescope or smart telescope is best."
        case (.deepSky, .openCluster):
            return "Use binoculars for wide clusters or a telescope for smaller ones."
        case (.deepSky, .planetaryNebula):
            return "Use a telescope; a nebula filter may help if available."
        case (.deepSky, .galaxy):
            return "Use a smart telescope, or observe visually from dark skies. Moonlight can wash out faint galaxy detail."
        case (.deepSky, .diffuseNebula):
            return "Use a telescope or smart telescope. A UHC or OIII filter may help, depending on the object."
        default:
            return "Recommended equipment: \(target.preferredEquipment.displayName)."
        }
    }

    private func observingNotes(
        for target: ObservableTarget,
        guide: TargetObservingGuide?
    ) -> String {
        if let observingNotes = guide?.observingNotes { return observingNotes }

        switch (target.type, target.deepSkyObjectType) {
        case (.moon, _): return "Craters and ridges show their strongest relief near the terminator, with shadows changing as the lunar phase changes."
        case (.planet, _): return "Planets appear as small disks; subtle features can look much less obvious than they do in photographs."
        case (.deepSky, .doubleStar):
            return "Compare the stars’ brightness and color once the pair is resolved; many doubles show a noticeable contrast."
        case (.deepSky, .planetaryNebula):
            return "It may appear as a small gray-green disk or ring rather than a bright, colorful photograph."
        case (.deepSky, .globularCluster):
            return "Expect a bright central glow with a granular outer halo; some edge stars may resolve under favorable conditions."
        case (.deepSky, .galaxy):
            return "Expect a brighter core with a diffuse halo or elongation; fine structure is often subtle visually."
        case (.deepSky, .openCluster):
            return "The cluster may appear loose or concentrated, with brighter members forming chains or patterns against the surrounding field."
        case (.deepSky, .diffuseNebula): return "Expect a faint gray glow with uneven brightness or dark lanes; photographs usually show more color and extent."
        default: return "Its appearance may be subtle, so compare it with nearby stars or familiar patterns."
        }
    }

    private static func directionText(_ direction: String) -> String {
        "Look \(directionName(direction))."
    }

    private static func directionName(_ direction: String) -> String {
        let names = ["N": "north", "NE": "northeast", "E": "east", "SE": "southeast",
                     "S": "south", "SW": "southwest", "W": "west", "NW": "northwest"]
        return names[direction.uppercased()] ?? direction.lowercased()
    }

    private static func altitudeText(_ altitude: Double) -> String {
        "About \(Int(round(altitude)))° high."
    }

    private static func azimuthText(_ azimuth: Double) -> String {
        "Azimuth \(Int(round(azimuth)))°"
    }

    private static func joinSentences(_ first: String, _ second: String?) -> String {
        [first, second].compactMap { $0 }.joined(separator: " ")
    }

    private static func dateNeutralized(_ text: String) -> String {
        text.replacingOccurrences(of: "tonight", with: "for this night", options: .caseInsensitive)
    }

    private static func overlapsPlacement(_ existing: String, _ placement: String) -> Bool {
        let existing = existing.lowercased()
        let placement = placement.lowercased()
        return (existing.contains("high in") && placement.contains("high in the sky"))
            || (existing.contains("astronomical darkness") && placement.contains("astronomical darkness"))
            || (existing.contains("weather") && placement.contains("weather"))
    }

    private static func recommendationSummaryWithoutEquipmentAdvice(_ summary: String) -> String? {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard containsPotentialEquipmentAdvice(trimmed) else { return trimmed }

        let retainedSentences = trimmed
            .split(whereSeparator: { ".!?".contains($0) })
            .compactMap { sentenceWithoutEquipmentAdvice(String($0)) }
        guard !retainedSentences.isEmpty else { return nil }
        return retainedSentences.map { "\($0)." }.joined(separator: " ")
    }

    private static func sentenceWithoutEquipmentAdvice(_ sentence: String) -> String? {
        var clauses = sentence
            .split(separator: ";", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        clauses = clauses.flatMap { clause in
            clause.split(separator: ",", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }

        clauses = clauses.flatMap { clause in
            let parts = clause.components(separatedBy: " and ")
            guard parts.count == 2 else { return [clause] }
            return parts.flatMap { part in
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                return isEquipmentAdvice(trimmed) ? [] : [trimmed]
            }
        }

        let retainedClauses = clauses.filter { !isEquipmentAdvice($0) }
        guard !retainedClauses.isEmpty else { return nil }
        return retainedClauses.joined(separator: ", ")
    }

    private static func isEquipmentAdvice(_ clause: String) -> Bool {
        let lowercased = clause.lowercased()
        let mentionsEquipment = ["binocular", "telescope", "low power", "higher power", "magnification"]
            .contains(where: lowercased.contains)
        guard mentionsEquipment else { return false }

        return [
            "use ", "best view", "best viewed", "through a telescope", "telescope target",
            "recommended equipment", "with binocular", "with a telescope", "low power", "higher power",
            "magnification", "resolve outer stars"
        ].contains(where: lowercased.contains)
    }

    private static func containsPotentialEquipmentAdvice(_ text: String) -> Bool {
        isEquipmentAdvice(text)
    }
}

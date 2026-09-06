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
                .init(kind: .findingTips, title: "Finding tips", text: findingTips(for: target, reasons: recommendation.reasons, guide: guide)),
                .init(kind: .bestEquipment, title: "Best equipment", text: equipment(for: target, guide: guide)),
                .init(kind: .observingNotes, title: "Observing notes", text: observingNotes(for: target, reasons: recommendation.reasons, guide: guide))
            ]
        )
    }

    private func whyRecommended(
        _ recommendation: TargetRecommendation,
        guide: TargetObservingGuide?
    ) -> String {
        let reasons = Set(recommendation.reasons)
        let summary = recommendation.summary
        let summaryLower = summary.lowercased()
        let hasBrightMoonImpact = reasons.contains(.moonInterference)
            || reasons.contains(.brightFullMoonDeepSkyImpact)

        var sentences: [String] = []
        if let placement = placementSentence(
            reasons: reasons,
            window: recommendation.visibilityWindow
        ) {
            sentences.append(placement)
        }
        if reasons.contains(.astronomicalDarkness) {
            sentences.append("Its best window falls during astronomical darkness.")
        } else if reasons.contains(.outsideAstronomicalDarkness) {
            sentences.append("Its best window falls in twilight rather than full astronomical darkness.")
        }
        if reasons.contains(.goodNightQuality) {
            sentences.append("The weather and sky quality look favorable.")
        } else if reasons.contains(.poorWeather) {
            sentences.append("Clouds or haze may interfere.")
        }
        if reasons.contains(.difficultTarget) {
            sentences.append("This is an intrinsically subtle target, so its defining detail may remain difficult even during a favorable window.")
        }

        if reasons.contains(.brightFullMoonDeepSkyImpact) {
            if recommendation.target.type == .moon {
                sentences.append("The bright full Moon is prominent, though surface relief is lower than near quarter phase and faint deep-sky contrast will suffer.")
            } else {
                sentences.append("The bright full Moon will reduce faint deep-sky contrast.")
            }
        } else if reasons.contains(.moonInterference) {
            if recommendation.target.deepSkyObjectType == .doubleStar {
                sentences.append("Moonlight is present but usually has little effect on separating this double star.")
            } else if recommendation.target.deepSkyObjectType == .galaxy {
                sentences.append("Moonlight may wash out faint galaxy detail during this window.")
            } else {
                sentences.append("Moonlight may reduce contrast during this window.")
            }
        }
        if hasBrightMoonImpact, let context = guide?.brightMoonContext {
            sentences.append(context)
        }
        if reasons.contains(.newMoonDarkSky) {
            sentences.append("The new Moon leaves a dark sky for deep-sky observing but offers little lunar detail.")
        }
        if reasons.contains(.moonSetsEarlyDarkSkyLater) {
            sentences.append("The Moon sets early, leaving a darker window later.")
        }
        if reasons.contains(.moonBelowUsefulWindow) {
            sentences.append("The Moon is visible only briefly during the useful window.")
        } else if reasons.contains(.moonVisibleUsefulWindow) {
            sentences.append("The Moon remains visible during the useful window.")
        }
        if reasons.contains(.excellentMoonCraterDetail) {
            sentences.append("The phase favors strong crater and ridge relief.")
        }
        if reasons.contains(.planetMoonlightResistant) {
            sentences.append("Moonlight has little effect on this bright planet.")
        }
        if reasons.contains(.convenientPlanetWindow) {
            sentences.append("The target is available during convenient evening hours.")
        } else if reasons.contains(.lateOrEarlyPlanetWindow) {
            sentences.append("Its best visibility is late at night or before dawn.")
        }

        if sentences.isEmpty,
           summaryLower != "visible tonight.",
           let compatibilitySummary = Self.recommendationSummaryWithoutEquipmentAdvice(summary) {
            sentences.append(Self.dateNeutralized(compatibilitySummary))
        }
        if sentences.isEmpty {
            sentences.append("This target should be worth observing during its best window.")
        }
        return sentences.joined(separator: " ")
    }

    private func placementSentence(
        reasons: Set<TargetRecommendationReason>,
        window: TargetVisibilityWindow
    ) -> String? {
        let isHigh = reasons.contains(.highAltitude)
        let isLow = reasons.contains(.lowAltitude)
        guard isHigh || isLow else { return nil }

        if let altitude = window.maxAltitude, let direction = window.direction {
            let placement = "During the best window, it reaches about \(Int(round(altitude)))° toward \(Self.directionName(direction))."
            return isLow
                ? "\(placement) It remains low enough that trees, hills, or buildings may obstruct it."
                : placement
        }
        if let altitude = window.maxAltitude {
            return "During the best window, it reaches about \(Int(round(altitude)))° altitude."
        }
        if isLow {
            return "It remains low during the best window, so trees, hills, or buildings may obstruct it."
        }
        return "It will be high in the sky during the best window."
    }

    private func findingTips(
        for target: ObservableTarget,
        reasons: [TargetRecommendationReason],
        guide: TargetObservingGuide?
    ) -> String {
        if let findingTips = guide?.findingTips { return findingTips }

        switch (target.type, target.deepSkyObjectType) {
        case (.moon, _):
            if reasons.contains(.brightFullMoonDeepSkyImpact) {
                return "At full phase, compare bright crater rays and broad differences in surface tone; the terminator is not prominent."
            }
            return "Trace the terminator, where long shadows make craters and ridges easier to recognize."
        case (.planet, _):
            return "Wait for brief moments of steady seeing, when fine detail may become easier to distinguish."
        case (.deepSky, .openCluster):
            return "Use a low-power sweep around the catalog position, then center the cluster before increasing magnification."
        case (.deepSky, .globularCluster):
            return "Use averted vision to secure the cluster, then increase magnification gradually only after it is centered."
        case (.deepSky, .planetaryNebula):
            return "Use direct and averted vision to distinguish nebulosity from field stars; adjust magnification after centering."
        case (.deepSky, .galaxy):
            return "Sweep slowly around the catalog position and use averted vision after centering the target."
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
            return "Binoculars can detect brighter globulars as compact glows; a visual telescope can resolve stars, while a Smart/EAA telescope can record more of the cluster."
        case (.deepSky, .openCluster):
            return "Use binoculars for wide clusters or a telescope for smaller ones."
        case (.deepSky, .planetaryNebula):
            return "Use a telescope or Smart/EAA telescope. For visual observing, choose a target-specific nebula filter when appropriate."
        case (.deepSky, .galaxy):
            return "Use binoculars or a low-power telescope for broad bright galaxies, a larger visual telescope for subtle structure, or a Smart/EAA telescope for faint extent."
        case (.deepSky, .diffuseNebula):
            return "Use a visual telescope or Smart/EAA telescope. For visual observing, filter choice depends on the target."
        default:
            return "Recommended equipment: \(target.preferredEquipment.displayName)."
        }
    }

    private func observingNotes(
        for target: ObservableTarget,
        reasons: [TargetRecommendationReason],
        guide: TargetObservingGuide?
    ) -> String {
        if let observingNotes = guide?.observingNotes { return observingNotes }

        switch (target.type, target.deepSkyObjectType) {
        case (.moon, _):
            if reasons.contains(.brightFullMoonDeepSkyImpact) {
                return "The disk is fully illuminated; crater rays and broad tone differences stand out, while most relief looks flatter than near quarter phase."
            }
            return "Craters and ridges show their strongest relief near the terminator, with shadows changing as the lunar phase changes."
        case (.planet, _): return "Planets appear as small disks; subtle features can look much less obvious than they do in photographs."
        case (.deepSky, .doubleStar):
            return "Compare the stars’ brightness and color once the pair is resolved; many doubles show a noticeable contrast."
        case (.deepSky, .planetaryNebula):
            return "Planetary nebulae range from tiny disks to broad faint glows; expect muted gray structure rather than photographic color."
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
        let names = [
            "N": "north", "NNE": "north-northeast", "NE": "northeast", "ENE": "east-northeast",
            "E": "east", "ESE": "east-southeast", "SE": "southeast", "SSE": "south-southeast",
            "S": "south", "SSW": "south-southwest", "SW": "southwest", "WSW": "west-southwest",
            "W": "west", "WNW": "west-northwest", "NW": "northwest", "NNW": "north-northwest"
        ]
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

    private static func recommendationSummaryWithoutEquipmentAdvice(_ summary: String) -> String? {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var retainedSentences: [String] = []
        trimmed.enumerateSubstrings(
            in: trimmed.startIndex..<trimmed.endIndex,
            options: .bySentences
        ) { substring, _, _, _ in
            guard let substring else { return }
            let sentence = substring.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sentence.isEmpty, !containsPotentialEquipmentAdvice(sentence) else { return }
            retainedSentences.append(sentence)
        }
        guard !retainedSentences.isEmpty else { return nil }
        return retainedSentences.joined(separator: " ")
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

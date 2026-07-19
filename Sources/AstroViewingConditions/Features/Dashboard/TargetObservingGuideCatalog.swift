enum TargetObservingGuideCatalog {
    private static let guidesByTargetID: [String: TargetObservingGuide] = {
        let guides = [
            TargetObservingGuide(
                targetID: "double-cluster",
                whyRecommendedOverride: .withPlacement("The Double Cluster is a rewarding target for this observing window."),
                findingTips: "Look in Perseus between Cassiopeia and the bright star Mirfak. Scan slowly between both clusters and compare their bright star patterns.",
                bestEquipment: "Use binoculars or a low-power telescope to keep both clusters in view.",
                observingNotes: "Two rich clusters sit close together in a Milky Way star field, with many bright blue-white stars and dense central concentrations."
            ),
            TargetObservingGuide(
                targetID: "m27",
                whyRecommendedOverride: .brightMoon("This large, bright planetary nebula is well placed during this observing window. The bright Moon may reduce contrast, but M27 is still worth trying."),
                findingTips: "Look in Vulpecula near Sagitta and Cygnus. Compare direct and averted vision to distinguish the dumbbell shape from nearby stars.",
                bestEquipment: "Use a telescope at low to moderate magnification. A nebula filter may help if available.",
                observingNotes: "Visually, M27 usually appears as a grayish fuzzy patch with a dumbbell or apple-core shape. Photos show much more color than you should expect at the eyepiece."
            ),
            TargetObservingGuide(
                targetID: "ngc7009",
                observingNotes: "Small bright planetary nebula that may look like a tiny blue-green oval; its Saturn-like extensions are subtle visually."
            ),
            TargetObservingGuide(
                targetID: "m31",
                whyRecommendedOverride: .withPlacement("Andromeda is a bright, large galaxy worth observing when conditions allow."),
                observingNotes: "Suburban views may show mostly the bright core rather than the broad, photo-like disk."
            ),
            TargetObservingGuide(
                targetID: "albireo",
                whyRecommendedOverride: .withPlacement("Albireo is a prominent double star."),
                observingNotes: "Look for the strong color contrast between the brighter golden star and its fainter blue companion."
            ),
            TargetObservingGuide(
                targetID: "epsilon-lyrae",
                whyRecommendedOverride: .withPlacement("Epsilon Lyrae is a compact double-star challenge."),
                observingNotes: "Each visible component can divide into a close pair, creating the Double Double when conditions permit."
            ),
            TargetObservingGuide(
                targetID: "m45",
                whyRecommendedOverride: .withPlacement("The Pleiades is a bright, broad open cluster."),
                bestEquipment: "Use binoculars or a low-power telescope to keep the whole cluster in view.",
                observingNotes: "A bright, broad pattern of blue-white stars; the faint reflection nebulosity seen in photographs is usually subtle visually."
            ),
            TargetObservingGuide(
                targetID: "m42",
                whyRecommendedOverride: .withPlacement("The Orion Nebula is a bright diffuse nebula."),
                bestEquipment: "Use binoculars or a telescope. Low to moderate magnification frames the nebula well.",
                observingNotes: "The nebula appears as a fuzzy gray or gray-green glow. Photographs show much more color and detail than the eyepiece view."
            ),
            TargetObservingGuide(
                targetID: "m5",
                whyRecommendedOverride: .withPlacement("M5 is a bright globular cluster."),
                bestEquipment: "Use a telescope; higher magnification may begin to resolve stars around the edges.",
                observingNotes: "A bright, compact glow with a granular halo; some outer stars may resolve under favorable conditions."
            ),
            TargetObservingGuide(
                targetID: "m3",
                whyRecommendedOverride: .withPlacement("M3 is a bright globular cluster."),
                bestEquipment: "Use a telescope; higher magnification may begin to resolve stars around the edges.",
                observingNotes: "A bright, compact glow with a granular halo; some outer stars may resolve under favorable conditions."
            ),
            TargetObservingGuide(
                targetID: "m16",
                bestEquipment: "Use a telescope. A nebula filter may help under dark skies.",
                observingNotes: "The open cluster is the easiest part. Faint surrounding nebulosity may appear under dark skies, but the Pillars of Creation are mainly an imaging and Hubble target."
            ),
            TargetObservingGuide(
                targetID: "m20",
                bestEquipment: "Use a telescope. A nebula filter may help under dark skies.",
                observingNotes: "Faint gray nebulosity and dark lanes may appear under good dark skies, but do not expect the vivid colors seen in photographs."
            ),
            TargetObservingGuide(
                targetID: "m33",
                whyRecommendedOverride: .withPlacement("This is a rewarding dark-sky challenge with low surface brightness, and it can be difficult from suburban skies."),
                bestEquipment: "A wide-field telescope or smart telescope is most helpful; dark, moonless skies are important.",
                observingNotes: "Expect a faint, diffuse glow with subtle spiral structure rather than a photo-like disk."
            ),
            TargetObservingGuide(
                targetID: "m101",
                whyRecommendedOverride: .withPlacement("This is a rewarding dark-sky challenge with low surface brightness, and it can be difficult from suburban skies."),
                bestEquipment: "A wide-field telescope or smart telescope is most helpful; dark, moonless skies are important.",
                observingNotes: "Expect a faint, diffuse glow with subtle spiral structure rather than a photo-like disk."
            ),
            TargetObservingGuide(
                targetID: "jupiter",
                observingNotes: "Look for dark cloud bands across the disk; finer features may appear only briefly."
            ),
            TargetObservingGuide(
                targetID: "saturn",
                observingNotes: "The rings are the most distinctive feature, with the planet’s globe appearing smaller and more subdued."
            ),
            TargetObservingGuide(
                targetID: "mars",
                observingNotes: "Mars appears as a small orange-red disk; subtle darker markings or a polar cap can be difficult to distinguish."
            ),
            TargetObservingGuide(
                targetID: "venus",
                observingNotes: "Venus is intensely bright and shows phases, but its cloud-covered disk has little visual surface detail."
            )
        ]
        return Dictionary(uniqueKeysWithValues: guides.map { ($0.targetID, $0) })
    }()

    static func guide(for targetID: String) -> TargetObservingGuide? {
        guidesByTargetID[targetID.lowercased()]
    }
}

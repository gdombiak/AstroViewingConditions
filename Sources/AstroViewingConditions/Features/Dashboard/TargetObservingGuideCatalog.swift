enum TargetObservingGuideCatalog {
    private static let guidesByTargetID: [String: TargetObservingGuide] = {
        let guides = [
            TargetObservingGuide(
                targetID: "double-cluster",
                whyRecommendedOverride: .always("The Double Cluster is a rewarding wide-field target during this observing window. Clouds may interfere, but if the sky clears, both clusters can fit beautifully in binoculars or a low-power telescope."),
                findingTips: "Look in Perseus between Cassiopeia and the bright star Mirfak. Scan slowly between both clusters and compare their bright star patterns.",
                bestEquipment: "Use binoculars or a low-power telescope to keep both clusters in view.",
                observingNotes: "Both clusters can fit in a binocular or low-power telescope view, surrounded by a rich Milky Way star field."
            ),
            TargetObservingGuide(
                targetID: "m27",
                whyRecommendedOverride: .brightMoon("This large, bright planetary nebula is well placed during this observing window. The bright Moon may reduce contrast, but M27 is still worth trying because its dumbbell shape can stand out better than many faint nebulae."),
                findingTips: "Look in Vulpecula near Sagitta and Cygnus. Compare direct and averted vision to distinguish the dumbbell shape from nearby stars.",
                bestEquipment: "Use a telescope at low to moderate magnification. A nebula filter may help if available.",
                observingNotes: "Visually, M27 usually appears as a grayish fuzzy patch with a dumbbell or apple-core shape. Photos show much more color than you should expect at the eyepiece."
            ),
            TargetObservingGuide(
                targetID: "ngc7009",
                observingNotes: "Small bright planetary nebula. In a telescope it may look like a tiny blue-green oval; the Saturn-like extensions need higher magnification and good seeing."
            ),
            TargetObservingGuide(
                targetID: "m31",
                observingNotes: "Easy to locate, but suburban views may show mostly the bright core rather than the broad, photo-like disk."
            ),
            TargetObservingGuide(
                targetID: "m45",
                bestEquipment: "Use binoculars or a low-power telescope to keep the whole cluster in view.",
                observingNotes: "Excellent beginner target. Its broad star pattern is best framed with binoculars or very low power."
            ),
            TargetObservingGuide(
                targetID: "m42",
                bestEquipment: "Use binoculars or a telescope. Low to moderate magnification frames the nebula well.",
                observingNotes: "Look for a fuzzy gray or gray-green glow in Orion's Sword. Photographs show much more color and detail than the eyepiece view."
            ),
            TargetObservingGuide(
                targetID: "m5",
                bestEquipment: "Use a telescope; higher magnification may begin to resolve stars around the edges.",
                observingNotes: "A bright fuzzy ball at low power; moderate or high magnification may resolve some outer stars in good conditions."
            ),
            TargetObservingGuide(
                targetID: "m3",
                bestEquipment: "Use a telescope; higher magnification may begin to resolve stars around the edges.",
                observingNotes: "A bright fuzzy ball at low power; moderate or high magnification may resolve some outer stars in good conditions."
            ),
            TargetObservingGuide(
                targetID: "m16",
                bestEquipment: "Use a telescope. A nebula filter may help under dark skies.",
                observingNotes: "The open cluster is the easiest part. Faint surrounding nebulosity may appear under dark skies, but the Pillars of Creation are mainly an imaging and Hubble target."
            ),
            TargetObservingGuide(
                targetID: "m20",
                bestEquipment: "Use a telescope. A nebula filter may help under dark skies.",
                observingNotes: "Look for faint gray nebulosity. Dark lanes may appear under good dark skies, but do not expect the vivid colors seen in photographs."
            ),
            TargetObservingGuide(
                targetID: "m33",
                whyRecommendedOverride: .withPlacement("This is a rewarding dark-sky challenge with low surface brightness, and it can be difficult from suburban skies."),
                bestEquipment: "Use low power under dark skies and try averted vision.",
                observingNotes: "Low surface brightness makes this galaxy a dark-sky challenge. Use low power, averted vision, and realistic expectations for subtle structure."
            ),
            TargetObservingGuide(
                targetID: "m101",
                whyRecommendedOverride: .withPlacement("This is a rewarding dark-sky challenge with low surface brightness, and it can be difficult from suburban skies."),
                bestEquipment: "Use low power under dark skies and try averted vision.",
                observingNotes: "Low surface brightness makes this galaxy a dark-sky challenge. Use low power, averted vision, and realistic expectations for subtle structure."
            )
        ]
        return Dictionary(uniqueKeysWithValues: guides.map { ($0.targetID, $0) })
    }()

    static func guide(for targetID: String) -> TargetObservingGuide? {
        guidesByTargetID[targetID.lowercased()]
    }
}

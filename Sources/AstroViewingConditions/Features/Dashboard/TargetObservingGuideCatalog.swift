enum TargetObservingGuideCatalog {
    private static let guidesByTargetID: [String: TargetObservingGuide] = {
        let guides = [
            TargetObservingGuide(
                targetID: "double-cluster",
                findingTips: "In Perseus, use the line between Cassiopeia and Mirfak to locate the pair, then sweep slowly between the two cluster centers.",
                bestEquipment: "Use binoculars or a low-power telescope to keep both clusters in view.",
                observingNotes: "Two rich clusters sit close together in a Milky Way star field, with many blue-white stars and dense central concentrations."
            ),
            TargetObservingGuide(
                targetID: "m27",
                brightMoonContext: "M27’s brighter central lobes may remain detectable despite the reduced contrast.",
                findingTips: "Find the arrow-shaped Sagitta inside the Summer Triangle; on a star chart, M27 is roughly 3° north of Gamma Sagittae in neighboring Vulpecula. Use averted vision after centering it.",
                bestEquipment: "Binoculars can detect it as a fuzzy patch. For visual observing, use a telescope at low to moderate magnification; a UHC filter is the best first choice, while OIII can emphasize inner structure. A Smart/EAA telescope can reveal fainter extent.",
                observingNotes: "M27 usually appears visually as a gray fuzzy patch with a dumbbell or apple-core shape. Photographs show much more color and extent than an eyepiece view."
            ),
            TargetObservingGuide(
                targetID: "ngc7009",
                findingTips: "In Aquarius, look about 1° west of Nu Aquarii. Start at low power to identify its tiny nonstellar disk, then increase toward 200× only as seeing allows.",
                bestEquipment: "Use a telescope at moderate to high magnification. Start unfiltered; a UHC or OIII filter can be tried for faint structure. A Smart/EAA telescope can reveal more of its morphology.",
                observingNotes: "Expect a tiny, bright oval. A blue-green tint is easier for some observers in 150–200 mm telescopes; the ansae are difficult in about 200 mm or more under steady seeing, and their end knots are harder still."
            ),
            TargetObservingGuide(
                targetID: "m31",
                findingTips: "From Mirach in Andromeda, follow the chain through Mu to Nu Andromedae; M31 lies about 1.5° from Nu. Use averted vision to trace beyond the bright center.",
                bestEquipment: "Use the naked eye for detection, binoculars for the broad disk and core, or a low-power wide-field telescope. A Smart/EAA telescope can reveal more of its faint extent.",
                observingNotes: "The bright core and an elongated diffuse disk are the normal visual result. The outer disk and dust lanes are much subtler than they appear in photographs."
            ),
            TargetObservingGuide(
                targetID: "albireo",
                findingTips: "Follow the long axis of Cygnus from Deneb to the star at the opposite end, then center Albireo before increasing magnification.",
                bestEquipment: "A small telescope at approximately 25–50× is sufficient to separate the pair.",
                observingNotes: "Once resolved, the brighter star usually appears golden and the fainter companion blue."
            ),
            TargetObservingGuide(
                targetID: "epsilon-lyrae",
                findingTips: "Find Vega, then center the nearby naked-eye companion. After centering the wide pair, increase magnification gradually during steady seeing without assuming both close pairs will split.",
                bestEquipment: "Use a telescope of about 75 mm aperture or more; 100 mm is preferred, with approximately 100× as a practical starting point.",
                observingNotes: "The two obvious stars each contain a much closer pair, giving this system its Double Double name. Resolving all four components is a demanding visual result, not a guarantee."
            ),
            TargetObservingGuide(
                targetID: "m45",
                findingTips: "Locate the compact Seven Sisters pattern in Taurus. To test suspected haze near Merope, move the bright star just outside the field and rule out dew, haze, or dirty optics.",
                bestEquipment: "Use the naked eye, binoculars, or a very low-power wide-field telescope. Visual nebula filters are not useful for its reflection nebulosity.",
                observingNotes: "A broad pattern of blue-white stars is the normal visual result. The photographic dust is not normally visible; faint true haze near Merope is an exceptional challenge in roughly a 150 mm (6-inch) telescope at low power, and glare can imitate it."
            ),
            TargetObservingGuide(
                targetID: "m42",
                findingTips: "Follow Orion’s Belt to the Sword and center its fuzzy middle star. After your eyes adapt, use direct and averted vision to compare the bright center with the fainter wings.",
                bestEquipment: "Use the naked eye for detection, binoculars for the broad glow, or a telescope for the Trapezium and finer structure. A Smart/EAA telescope can reveal fainter extent.",
                observingNotes: "Expect a fuzzy gray or gray-green glow with a brighter center; a telescope can show the Trapezium. Photographs reveal far more color and faint structure."
            ),
            TargetObservingGuide(
                targetID: "m5",
                findingTips: "In Serpens, use a star chart to locate M5 near 5 Serpentis. Center the compact glow before increasing magnification and use averted vision on its outskirts.",
                bestEquipment: "Binoculars can detect its compact glow; a telescope can begin to resolve stars around the edges, and a Smart/EAA telescope can record more of the cluster.",
                observingNotes: "Expect a bright, compact glow with a granular halo; some outer stars may resolve visually."
            ),
            TargetObservingGuide(
                targetID: "m3",
                findingTips: "Use a star chart to search the region between Arcturus and Cor Caroli. Center the compact glow before increasing magnification and use averted vision on its outskirts.",
                bestEquipment: "Binoculars can detect its compact glow; a telescope can begin to resolve stars around the edges, and a Smart/EAA telescope can record more of the cluster.",
                observingNotes: "Expect a bright, compact glow with a granular halo; some outer stars may resolve visually."
            ),
            TargetObservingGuide(
                targetID: "m16",
                findingTips: "In Serpens, start at Gamma Scuti; on a star chart, M16 lies about 2.5° west-northwest. Shield your eyes from stray light and use averted vision after centering the cluster.",
                bestEquipment: "Use a telescope or Smart/EAA telescope. For visual observing, try a narrowband UHC filter first; OIII can increase contrast in the brighter inner nebula. H-beta is not recommended.",
                observingNotes: "The embedded star cluster is much easier to detect than the faint gray nebula. The Pillars of Creation are not a routine visual expectation; imaging reveals them and much more of the surrounding gas."
            ),
            TargetObservingGuide(
                targetID: "m20",
                findingTips: "On a star chart, move a little more than 1° north from M8 to M20. Use averted vision to trace the nebula and its dark lanes after centering it.",
                bestEquipment: "Use 16×70-class binoculars for a challenging visual attempt or a telescope for more dependable visual observing. Try a UHC filter first and compare it with the unfiltered view; use a Smart/EAA telescope for electronically assisted observing.",
                observingNotes: "Smaller binoculars may show only the stars and a weak glow. In a telescope, expect faint gray nebulosity divided by dark lanes, not the vivid red and blue seen in photographs."
            ),
            TargetObservingGuide(
                targetID: "m33",
                findingTips: "Use the sharp tip of Triangulum as the starting point; M33 lies about 4° away. Sweep a wide field slowly and use averted vision to secure the diffuse glow.",
                bestEquipment: "Use binoculars or a low-power wide-field telescope for the broad galaxy, or a Smart/EAA telescope to reveal more structure.",
                observingNotes: "Expect a faint, diffuse glow. Hints of spiral structure are exceptional visually, while Smart/EAA observation can reveal the arms more clearly."
            ),
            TargetObservingGuide(
                targetID: "m101",
                findingTips: "Use Mizar and Alkaid in the Big Dipper as two corners of an approximate equilateral triangle, then sweep the third-corner region slowly with averted vision.",
                bestEquipment: "Use a low-power wide-field telescope for visual observation or a Smart/EAA telescope for the galaxy’s faint extent.",
                observingNotes: "Expect a very faint diffuse patch with an uneven or slightly brighter center. Spiral arms are exceptional visually but become clearer with Smart/EAA observation."
            ),
            TargetObservingGuide(
                targetID: "m57",
                findingTips: "In Lyra, sweep a little more than halfway from Sulafat toward Sheliak. At low power it can resemble an out-of-focus star; center it before increasing magnification.",
                bestEquipment: "Use a telescope, starting unfiltered. A UHC or OIII filter can modestly improve visual contrast, while a Smart/EAA telescope can reveal fainter structure.",
                observingNotes: "Expect a tiny, dim gray smoke ring with a darker center in a sufficient telescope. The strong color and fine structure in photographs are not normal visual expectations."
            ),
            TargetObservingGuide(
                targetID: "ngc7293",
                findingTips: "In Aquarius, use a star chart to find Upsilon Aquarii; the Helix lies about 1.2° west. Sweep at low power with averted vision because its light is spread across a large area.",
                bestEquipment: "Use a low-power wide-field telescope. An OIII filter is usually the strongest visual choice, with UHC also effective; a Smart/EAA telescope can reveal fainter extent and structure.",
                observingNotes: "Expect a very large, diffuse gray oval or ring with a darker center in a good visual view. Photographs show much more color and intricate structure."
            ),
            TargetObservingGuide(
                targetID: "m92",
                findingTips: "In Hercules, use a star chart to find Pi Herculis; move about 6° north—roughly the width of a typical 10× binocular field—to reach M92. Center the compact glow before increasing magnification.",
                bestEquipment: "Binoculars can detect its compact glow; a telescope can begin to resolve outer stars, and a Smart/EAA telescope can record more of the cluster.",
                observingNotes: "Binoculars show a compact fuzzy glow. A telescope reveals a bright concentrated core and can make the outer halo look granular or partly resolved."
            ),
            TargetObservingGuide(
                targetID: "jupiter",
                findingTips: "Use the compass direction and height above the horizon shown above to locate Jupiter. Then increase magnification gradually and wait for brief moments of steady seeing before judging fine detail.",
                bestEquipment: "Binoculars can show the four Galilean moons; use a telescope for the disk and cloud bands.",
                observingNotes: "The disk commonly shows two dark equatorial cloud bands; finer features may appear only briefly."
            ),
            TargetObservingGuide(
                targetID: "saturn",
                findingTips: "Use the compass direction and height above the horizon shown above to locate Saturn. Then increase magnification gradually and wait for steady moments before examining fine detail.",
                observingNotes: "The rings are the most distinctive feature, with the planet’s globe appearing smaller and more subdued."
            ),
            TargetObservingGuide(
                targetID: "mars",
                findingTips: "Use the compass direction and height above the horizon shown above to locate Mars. Then increase magnification gradually and wait for steady moments; its small disk may not support as much magnification as Jupiter or Saturn.",
                observingNotes: "Mars appears as a small orange-red disk; subtle darker markings or a polar cap can be difficult to distinguish."
            ),
            TargetObservingGuide(
                targetID: "venus",
                findingTips: "Use the compass direction and height above the horizon shown above to locate Venus. Then increase magnification gradually and wait for steadier moments before judging its phase.",
                bestEquipment: "Use the naked eye to locate Venus and a telescope to see its phase.",
                observingNotes: "Venus is intensely bright and shows phases, but its cloud-covered disk has little visual surface detail."
            )
        ]
        return Dictionary(uniqueKeysWithValues: guides.map { ($0.targetID, $0) })
    }()

    static func guide(for targetID: String) -> TargetObservingGuide? {
        guidesByTargetID[targetID.lowercased()]
    }
}

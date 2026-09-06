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
                targetID: "m13",
                findingTips: "Find the Keystone asterism in Hercules. M13 lies about one-third of the way from Eta Herculis toward Zeta Herculis; center it at low power, then increase magnification and use averted vision around its outskirts.",
                bestEquipment: "Binoculars can detect M13. Use a visual telescope with increased magnification to resolve stars; a Smart/EAA telescope can record more cluster members. Observe unfiltered.",
                observingNotes: "Expect a bright, round glow with a concentrated center. Under dark skies, a telescope can resolve stars around the outskirts; increasing aperture and steady seeing reveal progressively more stars toward the core."
            ),
            TargetObservingGuide(
                targetID: "m2",
                findingTips: "In Aquarius, use a star chart to find Sadalsuud, Beta Aquarii; M2 lies about 5° north. Center it before increasing magnification, then use averted vision around its outskirts.",
                bestEquipment: "Binoculars can detect M2. Use a visual telescope to begin resolving its stars; a Smart/EAA telescope can record more cluster members. Observe unfiltered.",
                observingNotes: "Expect a bright, concentrated globular glow. Its outer halo may look granular in a telescope, while resolving individual stars requires favorable conditions and additional aperture."
            ),
            TargetObservingGuide(
                targetID: "m30",
                findingTips: "In Capricornus, use a star chart to move about 3° east from Zeta Capricorni to 41 Capricorni; M30 lies less than 0.5° west of 41. Center it before increasing magnification and use averted vision around its outskirts.",
                bestEquipment: "Binoculars can detect M30 but do not normally resolve its stars. Use a visual telescope for partial resolution; a Smart/EAA telescope can record more cluster members. Observe unfiltered.",
                observingNotes: "Expect a small, round misty glow with a brighter, tightly concentrated center. A telescope may resolve some outer stars under dark, steady conditions, while the dense center generally remains unresolved."
            ),
            TargetObservingGuide(
                targetID: "m52",
                findingTips: "In Cassiopeia, follow the line from Schedar through Caph and extend it about 6° beyond Caph to M52. Sweep at low power, then increase magnification after centering the cluster.",
                bestEquipment: "Binoculars can detect M52. Use a visual telescope to resolve its many faint members; a Smart/EAA telescope can record more cluster members. Observe unfiltered.",
                observingNotes: "Expect a compact, grainy concentration in a crowded star field. A telescope resolves it into a rich group dominated by faint stars, with a few brighter members making the cluster easier to recognize."
            ),
            TargetObservingGuide(
                targetID: "m11",
                findingTips: "In Scutum, use a star chart to find Beta Scuti; M11 lies about 2° southeast. Sweep at low power through the dense Milky Way field, then increase magnification after centering the cluster.",
                bestEquipment: "Binoculars can detect M11. Use a visual telescope to resolve its dense stellar population; a Smart/EAA telescope can record more cluster members. Observe unfiltered.",
                observingNotes: "Binoculars show a compact triangular patch. A telescope reveals an unusually rich, concentrated open cluster whose brighter stars can suggest a wedge or rough V; the pattern's clarity depends on magnification and sky conditions."
            ),
            TargetObservingGuide(
                targetID: "m36",
                findingTips: "In Auriga, use a star chart to move about 6° north-northeast from Elnath, Beta Tauri, to M36. Sweep at low power, then center the cluster before increasing magnification.",
                bestEquipment: "Binoculars can detect M36; use a visual telescope to separate more of its stars. A Smart/EAA telescope can record more cluster members. Observe unfiltered.",
                observingNotes: "Expect a relatively small, compact group of conspicuously bright stars with open space between them. A telescope makes the cluster easier to separate from the surrounding Milky Way field; the pinwheel impression is subjective rather than guaranteed."
            ),
            TargetObservingGuide(
                targetID: "m38",
                findingTips: "After locating M36 in Auriga, move about 2.5° northwest to M38. Sweep with a wide field to secure the cluster, then increase magnification while keeping its broader extent in view.",
                bestEquipment: "Binoculars are preferred for M38. Use a low- to moderate-power visual telescope to resolve more members; a Smart/EAA telescope can record more cluster members. Observe unfiltered.",
                observingNotes: "Expect a larger, looser, and more irregular group than M36. Its brighter stars may suggest an oblique cross or starfish pattern, but the resemblance depends on field orientation and which stars are visible."
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
                targetID: "m51",
                findingTips: "From Alkaid at the end of the Big Dipper’s handle, move about 3.5° southwest into Canes Venatici. Sweep slowly with averted vision; after detecting M51, look for its smaller companion immediately beside it.",
                bestEquipment: "Binoculars are not a dependable choice. Use a visual telescope and observe unfiltered; a Smart/EAA telescope can reveal the spiral pattern and interaction with the companion more clearly.",
                observingNotes: "The normal visual baseline is two small, unequal glows: M51 and its companion NGC 5195. Spiral structure is difficult and requires unusually favorable darkness, transparency, aperture, and observing skill; a connecting bridge is an exceptional visual result, not a promise. Smart/EAA and photographs show the interaction much more clearly."
            ),
            TargetObservingGuide(
                targetID: "m64",
                findingTips: "In Coma Berenices, use a star chart to find 35 Comae Berenices; M64 lies about 1° northeast. Sweep slowly with averted vision, then compare moderate magnifications after centering the galaxy.",
                bestEquipment: "Binoculars are unsuitable for M64. Use a visual telescope and observe unfiltered; a Smart/EAA telescope can reveal the dust feature and faint outer extent more readily.",
                observingNotes: "Expect an oval diffuse glow with a brighter center. The feature that gives M64 its ‘Black Eye’ nickname is challenging visual detail: it may appear with sufficient aperture, magnification, darkness, and transparency, but is not guaranteed. Smart/EAA and photographs reveal it much more readily."
            ),
            TargetObservingGuide(
                targetID: "m77",
                findingTips: "In Cetus, use a star chart to find Delta Ceti; M77 lies a little less than 1° southeast. Center it at low power, then increase magnification and use averted vision around its outskirts.",
                bestEquipment: "Binoculars are unsuitable for M77. Use a visual telescope, starting unfiltered; a Smart/EAA telescope can reveal the faint outer galaxy and surrounding structure more clearly.",
                observingNotes: "Expect a small, bright central region surrounded by a much fainter diffuse halo. Dark, transparent conditions may reveal more of the outer galaxy, but its photographed spiral structure is not a routine visual expectation. Smart/EAA and photographs show substantially more extent."
            ),
            TargetObservingGuide(
                targetID: "m81",
                findingTips: "Extend the line from Phecda through Dubhe in the Big Dipper by roughly the same distance toward 24 Ursae Majoris; the M81/M82 pair lies before that star. Sweep at low power to secure both galaxies, then center M81.",
                bestEquipment: "Binoculars can detect M81 and M82 in one field. Use a low-power visual telescope for the shared field and more magnification for M81; a Smart/EAA telescope can reveal more of its disk. Observe unfiltered.",
                observingNotes: "M81 normally appears as a smooth oval glow with a conspicuously brighter center. Its faint outer halo depends strongly on darkness and transparency, while spiral arms are difficult visual detail even with substantial aperture. Smart/EAA and photographs reveal the arms much more clearly."
            ),
            TargetObservingGuide(
                targetID: "m82",
                findingTips: "Locate the M81/M82 field by extending the line from Phecda through Dubhe toward 24 Ursae Majoris. M82 lies about 0.6° north of M81; use averted vision along its long axis after centering it.",
                bestEquipment: "Binoculars can detect M82 in the same field as M81. Use a low-power visual telescope for the pair and moderate magnification to study M82; a Smart/EAA telescope can reveal more internal structure and outer material. Observe unfiltered.",
                observingNotes: "M82 appears as a narrow, elongated streak, distinctly thinner than M81. Under dark, transparent skies, additional aperture may reveal uneven brightness or dark interruptions across it. The colored starburst plumes prominent in photographs and Smart/EAA are not a normal visual expectation."
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

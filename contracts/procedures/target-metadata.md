# Target metadata / requirement resolution (unreleased 1.0)

## Assessment and boundary review

**Partially Agree**, assessed on clean `feature/astro-engine-cli`. Production
justifies portability, but does not justify a single all-target metadata DTO.
Chosen design: **C + D**, three small public capabilities with shared canonical
product data and minimal procedures. All have `since: "1.0.0"`, fixture range
`>=1.0.0 <2.0.0`; public capability count rises from 18 to 21. Engine and Python
package remain unreleased `1.0.0`.

- **A (requirements alone):** coherent but incomplete: leaves solar candidate
  literals and deep-sky sensitivity derivation independently duplicated.
- **B (one broad metadata capability):** unnecessarily couples static catalog
  acquisition, injected-target requirements, and a numeric derivation. Forces
  unrelated fields into an output and obscures missing-versus-derived sensitivity.
- **C (separate small boundaries):** selected. Each has a distinct production
  caller and can be composed independently without live astronomy.
- **D (canonical data plus resolver):** selected together with C. Requirements
  are full records, not a second procedural switch table in each language.
- **E (extend `catalog.deep_sky` or `equipment.match`):** rejected. Catalog
  identity is already shared; its existing 29-entry DTO/equality stays frozen.
  Matching must continue accepting already-resolved requirements. Data only,
  without CLI procedures, would make the Bot reproduce precedence/derivation.

## Source archaeology and ownership

Production sources inspected (repository-relative paths):

- `apps/ios/Sources/SharedCode/Core/Models/TargetEquipmentRequirements.swift`:
  normalization, eight typed fallbacks, empty default, 20 full-record overrides.
- `packages/astro-engine-swift/Sources/AstroEngine/Models/TargetEquipmentRequirement.swift`:
  initializer defaults, enums, paired Smart/EAA threshold invariants.
- `packages/astro-engine-swift/Sources/AstroEngine/Catalog/TargetDomain.swift` and
  `Catalog/DeepSkyCatalog.swift`: domain enums, canonical decoding and identity.
- `apps/ios/Sources/SharedCode/Core/Models/ObservableTarget.swift`: optional
  sensitivity and its 0...1.5 clamp; difficulty clamp; presentation concerns.
- `apps/ios/Sources/SharedCode/Core/Services/DeepSkyCatalogService.swift`:
  default candidate construction, injected catalogs, derived sensitivity and
  separate live deep-sky position/window generation.
- `apps/ios/Sources/SharedCode/Core/Services/TargetRecommendationService.swift`:
  specialized-provider dispatch, generic scoring adapter, stable ranking.
- `apps/ios/Sources/SharedCode/Core/Services/MoonRecommendationService.swift` and
  `PlanetRecommendationService.swift` (including `PlanetOrbitalElements`):
  specialized live facts/scoring and dormant planet enum support.
- `apps/ios/Sources/SharedCode/Core/Models/EquipmentMatching.swift`,
  `EquipmentSessionSelection.swift`, and
  `apps/ios/Sources/AstroViewingConditions/Features/Dashboard/DashboardView.swift`:
  requirements feed matching; `.filter` retains scores/order, dashboard truncates
  afterward. No inventory or `.any` bypasses equipment filtering.
- `packages/astro-engine-swift/Sources/AstroEngine/Scoring/EquipmentMatchingRules.swift`,
  `Phase15Contracts.swift`, `TargetScoring.swift`; Python `equipment.py`,
  `targets.py`, `catalog.py`: existing evaluator/scoring/transport boundaries.
- `contracts/data/catalog/deep-sky.json`, `equipment-limits.json`,
  `contracts/data/calibration/target-scoring.json`, `equipment-matching.json`:
  canonical identity, inventory limits, sensitivity calibration, matching rules.
- Production regression tests: `EquipmentTests`, `CuratedDeepSkyCatalogTests`,
  `TargetRecommendationScorerTests`, `WidgetTonightTargetsTests`.

The existing iOS curated catalog already reads the portable 29-entry JSON; there
is no separate conflicting iOS catalog to reconcile. Its values and ordering are
unchanged. Inventory limits and matching calibration are unrelated to resolution
and remain untouched. No stale numeric values are silently corrected.

### Actual default candidates

Solar candidates, **in this order**, are Moon, Venus, Mars, Jupiter, Saturn.
Then the deep-sky catalog, **in this order**:

`m13, m31, m2, m30, m52, m11, m36, m38, m57, m27, ngc7009, ngc7293,
m51, m64, m77, m81, m82, m92, albireo, epsilon-lyrae, m45, m42,
double-cluster, m5, m3, m16, m20, m33, m101`.

Deep-sky types and concrete members:

| Type | IDs |
|---|---|
| globularCluster | m13, m2, m30, m92, m5, m3 |
| galaxy | m31, m51, m64, m77, m81, m82, m33, m101 |
| openCluster | m52, m11, m36, m38, m45, double-cluster |
| planetaryNebula | m57, m27, ngc7009, ngc7293 |
| doubleStar | albireo, epsilon-lyrae |
| diffuseNebula | m42, m16, m20 |

No Mercury, Uranus, Neptune, Earth, satellite or meteor-shower default
recommendation candidates are added. The original naked-eye planet fallback set
includes Mercury; that is a dormant fallback rule, not candidate support. The
host typed resolver preserves default-empty behavior for existing satellite and
meteor-shower enum values. Public explicit types are restricted to the three
currently produced types (`moon`, `planet`, `deepSky`). Unknown identity with an
explicit supported type tests existing injected-target fallbacks, not new default
candidate support. Both production double stars are overridden; their type
fallback is exercised only through an injected unknown identity.

## Canonical data versus procedure

`contracts/data/catalog/target-requirements.json` owns the original initializer
values: one empty/default record, eight full fallback records, 20 full overrides,
and the original naked-eye planet ID set. Full records make override replacement
unambiguous. Missing modeled values are explicit JSON null. No merge/inheritance
from a fallback applies to overrides.

`contracts/data/catalog/solar-system.json` owns ordered objective candidate
facts: `id`, `type`, `preferred_equipment`, `difficulty`, `observing_intent`.
Names/images/copy stay in the host. Existing snake-case deep-sky catalog enum
spellings remain frozen; the new boundaries use the existing matching/scoring
camel-case enum spellings to compose directly with those contracts.

Sensitivity thresholds remain in the existing
`calibration/target-scoring.json#/moon/deep_sky_interference_sensitivity`.
Do not store derived sensitivity per catalog row or duplicate calibration.

Both implementations load these same files. Apple runtime bundles receive only
generated, gitignored copies through `scripts/bundle-engine-data`; Xcode input
and output declarations include both new catalog files. Python uses the existing
contracts-root discovery/installation mechanism with no package-local copies.

## `targets.requirements`

Input is a JSON object with required nonempty string `id`, optional `type`,
optional `object_type`; unknown keys are rejected.

1. Trim Foundation `CharacterSet.whitespacesAndNewlines`, then lowercase ID.
   This includes U+200B and excludes U+001C...U+001F; Python uses the same set.
   No aliases, internal-space removal, hyphen rewriting, or name search.
2. If `type` is absent, `object_type` must also be absent. Look up normalized ID
   in the canonical 29 deep-sky entries, then five solar entries. Use their type
   and subtype. Unknown ID is a validation error; never invent requirements.
3. If `type` is supplied it must be `moon`, `planet`, or `deepSky`. The optional
   subtype is one of the six camel-case deep-sky types or null. Missing/null
   subtype means nil; **do not infer it from ID in this explicit-type form**.
   A valid subtype on a non-deep-sky target is ignored, as in production.
4. Validate all supplied enums before resolving, even if an override exists.
5. A normalized-ID override wins **regardless of supplied type/subtype** and
   replaces the entire requirement. A known-ID/type mismatch is not rejected.
6. Otherwise use moon/planet fallback, or deep-sky subtype fallback. Deep sky
   with nil subtype gets the empty/default record. For planet fallback only,
   Mercury/Venus/Mars/Jupiter/Saturn IDs change naked-eye suitability to preferred.
   An uncataloged planet uses unsupported naked-eye suitability.

Result has exactly `requirement` and `is_planet` (from the effective supplied or
canonical type, independently of override). `requirement` uses the existing
`equipment.match` field names:

- `naked_eye_suitability`, `binocular_suitability`, `smart_eaa_suitability`;
- `preferred_binocular_magnification`: inclusive two-number range or null;
- `practical_binocular_aperture_mm`, `preferred_binocular_aperture_mm`;
- `practical_visual_aperture_mm`, `preferred_visual_aperture_mm`;
- `practical_smart_eaa_aperture_mm`, `preferred_smart_eaa_aperture_mm`;
- `framing`: `veryWide`, `wide`, `medium`, or `compact`;
- `magnification_benefit`: Boolean.

The empty/default record is unsupported naked eye, unsuitable binoculars,
poorMatch Smart/EAA, medium framing, false magnification benefit, all numeric
fields null. This is an unknown requirement, not a positive suitability claim.
There is no numeric FOV requirement or telescope magnification range in production.
Mode suitability is metadata; the actual observing mode comes from matching.

Overrides: `m31, m42, m45, double-cluster, m36, m38, m77, m51, m101, m33,
m64, m20, albireo, epsilon-lyrae, m57, ngc7009, ngc7293, jupiter, saturn, mars`.
M77 preserves unsuitable binoculars, 150/250 mm visual, 30/50 mm Smart/EAA,
compact framing, true magnification benefit and preferred Smart/EAA. Its omitted
binocular fields stay null; they are not inherited from galaxy fallback. Albireo
keeps 50/50 mm visual and false magnification benefit. M20 keeps 15...20 binocular
magnification and 70/70 mm binocular thresholds. Planets retain poorMatch
Smart/EAA and null Smart/EAA apertures; Moon has distinct supported Smart/EAA.
These are production quirks, not cleanup opportunities.

Composition: resolve → pass the result's `requirement` and `is_planet` plus
selected `capabilities` to `equipment.match` → later filter already-ranked
recommendations. Matching has no target lookup. No recommendation is rescored or
reordered here. No mixed composition is implemented.

## `catalog.solar_system`

Input must be `{}`. Result is `{"entries": [...]}` in canonical order, with
exact objective values (Moon .1/easy/nakedEye; Venus .1/easy/nakedEye;
Mars .2/standard/nakedEye; Jupiter .25/easy/smallTelescope;
Saturn .35/easy/smallTelescope). Candidate `preferred_equipment` is explicit
catalog metadata, **not derived from requirement fallback**. Requirements still
resolve separately: Venus/ Moon use type fallbacks; Mars/Jupiter/Saturn overrides.
Solar candidates do not store sensitivity, positions, windows, phase or scores.
Host `ObservableTarget.moonInterferenceSensitivity` remains nil for them.

## `targets.moon_sensitivity`

Input: required `object_type` from the six deep-sky camel-case values, optional
finite numeric `surface_brightness` (magnitudes per square arcminute) or null.
Missing brightness equals null. Unknown keys/enums, numeric strings, Booleans and
nonfinite numbers are errors, even for non-planetary-nebula types.

- Any non-planetary-nebula type → 1, regardless of brightness.
- Planetary nebula with missing brightness → 1.
- Planetary nebula with brightness <= 10 → 0.65.
- Planetary nebula with brightness >= 13 → 1.2.
- Otherwise → 1.

Return exactly `{"sensitivity": number}` using existing calibration values.
There is no interpolation, live Moon input, or Moon penalty calculation. No
production-derived zero/fully insensitive case exists; the least-sensitive case
is 0.65. Double stars still derive 1; their small Moon-scoring ceiling belongs to
unchanged `targets.recommend`, not this procedure. The host still applies its
existing model clamp after deriving the value.

## Equality, fixtures and failures

Policies `target_requirements`, `solar_system_catalog`, and
`target_moon_sensitivity` are exact, including nulls, enum values, record keys,
numbers, ordered ranges and solar entries. No tolerances or English output.
Validation errors are code `validation`, message `invalid <capability> input`.
Existing host envelope validation still handles missing/non-object `injected`.

Manual fixtures under `fixtures/capabilities/target-metadata` freeze selected
original production literals and arithmetic, not outputs generated by either new
engine. They cover all 20 overrides, all six subtype fallbacks, Moon/planet
fallbacks, empty requirements, unknown IDs, mismatch precedence, normalization,
malformed inputs, exact sensitivity thresholds and solar order. Expected files
are frozen snapshots, not references back to the moved requirements data.

## Integration and deferred work

The iOS requirements type is now a thin typed adapter. Its catalog provider uses
shared solar facts and shared sensitivity derivation, including injected catalog
surface brightness. Host names, credits and images stay local. Deep-sky live
position/window code is unchanged. Watch/widget packaging receives the same new
resources; payload/ranking/presentation logic is unchanged.

Still required later: deep-sky live facts and windows, specialized Moon facts and
recommendation policy/scoring, production planet astronomy and recommendation
policy/scoring, mixed-target composition and equipment filtering integration for
the Bot, Best Nearby/forecast-horizon policies, Bot acquisition/state/aliases and
host presentation. No later slice is marked complete; no release/version bump.

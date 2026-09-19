# equipment.match — normative resolved-requirement matching

Introduced under **unreleased 1.0.0**. This is the existing production selection
algorithm, not equipment inventory validation or target requirement discovery.
The canonical preference weights are `data/calibration/equipment-matching.json`.

## Boundary and JSON

Normal envelope: `capability: "equipment.match"`, with `injected` containing:

- `requirement`: required object of resolved facts below;
- `capabilities`: required ordered array of instruments;
- `is_planet`: optional boolean, default false (only affects naked-eye preferred level).

Each instrument has a unique nonempty caller-supplied `key`, `type` in
`nakedEye`, `binoculars`, `visualTelescope`, `smartTelescope`, and optional/null
`aperture_mm` and `magnification`. Names, UUIDs, storage and display units are
absent. A host normalizes aperture to millimeters before calling. Finite zero,
negative or missing instrument measurements are accepted as unavailable/limited
facts, matching production defensive behavior. They are not saved-inventory
validation errors. All provided measurements, including unused ones, must follow
the Phase 15 numeric profile: JSON number, finite, absolute value <=1e9, never a
boolean. All unknown enum values and malformed optional values are errors.

Requirement fields:

| Field | Default / allowed values |
|---|---|
| `naked_eye_suitability` | `unsupported`; or `challenging`, `preferred` |
| `binocular_suitability` | `unsuitable`; or `practical`, `preferred` |
| `smart_eaa_suitability` | `poorMatch`; or `supported`, `preferred` |
| `framing` | `medium`; or `veryWide`, `wide`, `compact` |
| `magnification_benefit` | false; boolean |
| `preferred_binocular_magnification` | absent/null, or positive ordered `[lower, upper]`, inclusive |
| `practical_binocular_aperture_mm`, `preferred_binocular_aperture_mm` | absent/null or positive numeric threshold |
| `practical_visual_aperture_mm`, `preferred_visual_aperture_mm` | absent/null or positive numeric threshold |
| `practical_smart_eaa_aperture_mm`, `preferred_smart_eaa_aperture_mm` | absent/null or positive numeric threshold; must be paired |

When both aperture thresholds exist, preferred must be >= practical. Partial
binocular/visual requirements produce `unknownRequirement`; partial smart/EAA
requirements are invalid, matching the existing model precondition. Required
objects/arrays may be empty but not null. Null does not substitute for enum or
boolean defaults. Unknown extra fields are ignored. Keys use UTF-8 identity.

Success result is `{"match": null}` only for an empty capability array. Otherwise:

```
{"match": {"key": "chosen", "other_suitable_keys": ["another"],
           "level": "excellent", "reason": "preferredAperture", "mode": "visual"}}
```

All output fields and ordering compare exactly. `explanation` is absent: English
copy belongs to the host. Invalid injected facts return code `validation`, message
`invalid equipment.match input`; shared envelope/ref errors retain existing policy.

## Candidate decision procedure

Evaluate in the listed order. The mode is `nakedEye` for naked-eye capabilities,
`visual` for binoculars/visual telescopes, and `electronicallyAssisted` for smart
ones. Preferences below name entries in canonical `preferences`; numeric values
are data, not independently copied into either implementation.

| Instrument / first matching condition | Level | Reason | Preference key |
|---|---|---|---|
| Naked eye unsupported | poor | nakedEyeUnsupported | none |
| Naked eye challenging | challenging | nakedEyeChallenging | naked_eye_challenging |
| Naked eye preferred | good for planet, otherwise excellent | nakedEyePreferred | naked_eye_preferred |
| Binocular suitability unsuitable | poor | modeMismatch | none |
| Binocular aperture missing/nonpositive or either aperture requirement missing | challenging | unknownRequirement | unknown |
| Binocular aperture below practical | challenging | apertureLimited if magnification in range; otherwise apertureAndMagnificationLimited | binocular_aperture_limited |
| Binocular magnification not in range | challenging | binocularMagnificationTooLow / binocularMagnificationTooHigh / binocularMagnificationUnknown | binocular_magnification_limited |
| Remaining binocular | excellent if suitability preferred AND aperture >= preferred; otherwise good | see below | binocular_preferred if excellent, otherwise binocular_practical |
| Visual aperture missing/nonpositive or either requirement missing | challenging | unknownRequirement | unknown |
| Visual veryWide and aperture below practical | challenging | apertureLimited | aperture_limited |
| Visual veryWide, sufficient practical aperture | good | framingLimited | very_wide_visual |
| Remaining visual aperture >= preferred | excellent | magnification if benefit, otherwise preferredAperture | visual_preferred + framing adjustment |
| Remaining visual aperture >= practical | good | practicalAperture | visual_practical + framing adjustment |
| Remaining visual | challenging | apertureLimited | aperture_limited |
| Smart aperture missing/nonpositive | poor | apertureLimited | none |
| Smart suitability poorMatch | poor | modeMismatch | none |
| Smart requirements missing | challenging | unknownRequirement | unknown |
| Smart aperture below practical | challenging | apertureLimited | aperture_limited |
| Smart supported | good | electronicSupport | electronic_supported |
| Smart preferred and aperture >= preferred, broad framing | good | framingLimited | electronic_practical |
| Smart preferred and aperture >= preferred, other framing | excellent | electronicAssistance | electronic_preferred |
| Remaining smart preferred | good | electronicAssistance | electronic_practical |

Binocular magnification is unknown if the range or measurement is missing, or
measurement <=0. Otherwise lower and upper limits are inclusive. Below and above
are distinct reasons. For remaining binoculars, reason is `wideField` for wide or
veryWide framing; otherwise `binocularMagnificationInRange` when aperture >=
preferred, else `practicalAperture`. Visual framing adjustment is canonical
`wide_visual_adjustment` for exactly `wide`, otherwise zero. Broad smart framing
means `wide` or `veryWide`. Supported smart equipment is not downgraded for broad
framing; the broad branch is specifically for preferred suitability at preferred
aperture. No aperture maximum is imposed here.

## Selection

Sort all candidates by level (`excellent`, `good`, `challenging`, `poor`), then
preference descending, aperture descending (missing = 0), magnification descending
(missing = 0), then key in lexicographic UTF-8 byte order. Do not normalize Unicode.
Select the first even if it is poor. Other suitable keys are the remaining
excellent/good candidates in that order; exclude challenging/poor candidates.

Production previously used `0` for naked eye and `1` plus a saved UUID string for
its final tie-break. The host supplies those same stable keys to engine reuse, so
renaming equipment still cannot affect selection. The public contract accepts
arbitrary stable caller keys and never generates UUIDs.

Target-specific aperture/magnification thresholds are already resolved by the
host's `TargetEquipmentRequirements` fallbacks/overrides. Moving that catalog or
its persistence is not required for this capability. Inventory entry limits in
`equipment-limits.json` remain unbound: 100x/300mm/2000mm entry limits are not
matching thresholds. Only the actual matching preferences became newly canonical
calibration. SwiftUI, saving, session selection and English explanations stay in
the host.

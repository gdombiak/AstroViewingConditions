# Lunar parity review — 2026-09-06

Initial verdict: **Partially Agree**. The inherited recommendation extraction was
faithful, but the observation model and public resource bounds had demonstrable
failures. The existing implementation was corrected in place. No known blocker
remains in the validated slice.

## Corrections made

| Severity | Finding and correction |
|---|---|
| P1 | Skyfield did not meet the observation contract. At 20.517045369405356 N, 26.523419481713518 W on 2026-03-01T00:00:00Z, azimuth differed by 112.217801°. For New York (40.7, -74), 2026-08-29T00:00:00Z–11:46:30Z, Swift found a set at 11:46:28Z while Skyfield returned null and always_up=true. With the user's explicit approval, ported the pinned production SunCalc lunar facts to Python. Swift astronomy was not replaced. |
| P2 | The 1440-row preflight omitted the explicit endpoint. A 60-second cadence over 86370 seconds passed and emitted 1441 rows. Reserve a row for a non-divisible endpoint; exactly 1440 divisible samples remain accepted and compose into the recommendation consumer. |
| P2 | Cadence also controls the minimum rise/set search duration, but had no upper bound. Bound cadence as well as positive night span to 93600 seconds, including inverted nights. |
| P2 | Fractional cadence could emit duplicate floored timestamps, rejected by the downstream consumer, and repeated addition on different epochs could disagree. Require integral cadence, retaining the non-advancing preflight and its sample_cap error. Python preflight now uses Swift's reference epoch. |
| P2 | Portable Swift observation inherited the host timezone convention for phase calculation. Pin only the portable entry to UTC; keep the original iOS convention. |
| P3 | Python numeric conversion could leak OverflowError for oversized integers; normalize this to validation. Diagnostics now read canonical weights/cap instead of duplicating scoring literals. |
| P3 | Corrected the documented two-root ordering and height-evaluation count. Added a Moon-specific event comparator for legitimate bounded forward spill into early 2050; existing solar comparison rules are unchanged. Cyclic comparison rejects out-of-range equivalents. |

## Deliberately preserved

Production uses midpoint `start + max(span, 0)/2`; rise/set searches
`max(span, cadence)` using hourly quadratics and the unrefracted geocentric
parallax/refraction/semidiameter threshold. Flags start from the sign at hour zero
and clear only on the opposite crossing. Recommendation visibility instead uses
strict refracted sampled altitude >0. These differences are production behavior,
not bugs to normalize away.

Also preserved: inclusive useful-window clipping; best-window fallback without
clipping that window to the night; earliest altitude tie; nullable azimuth; literal
1800-second extension and end clipping; useful-sample denominator; strict hourly
rating overlap and cloud fallback; ordered binary64 rating summation; all phase
and illumination branch boundaries; illumination <=8 score cap; strict early-set
and poor-weather boundaries; reason ordering/fallback; alwaysDown with visible
samples; rounded 16-point compass.

The seven oracle math functions (visibilityWindow, score, phaseQuality, reasons,
visibleFraction, weatherQuality, compassDirection) were compared directly with
committed HEAD and match byte-for-byte. The host summary body also matches HEAD.
The oracle has no new engine-helper or calibration dependency.

## Architecture and public surface

There are **25 unique public capabilities**, with catalog order matching the
Python CLI allow-list. The new Swift eval dispatches are exercised by parity:

- `astronomy.moon_observation`: bounded night-scoped provider facts. Both hosts
  now use the production SunCalc analytic model; Python needs no ephemeris file
  or provider network access for this capability.
- `targets.moon_recommendation`: deterministic injected-observation scoring,
  visibility window and objective reasons. No live astronomy.

Production still follows DefaultTargetRecommendationService →
DefaultMoonTargetRecommendationProvider → SunCalcMoonAstronomyProvider →
SunCalcMoonObservationSampler, then delegates useful-window selection,
visibility, score, phase quality, reasons, fraction, weather quality and compass
to AstroEngine.MoonRecommendation.

Host responsibilities retained: target-type guard, summary and poor-conditions
presentation policy, phase-name/emoji presentation, DTO identity construction,
and validation/debug logging. The existing internal observation DTO's phase-name
behavior is preserved; the public transport omits it.

Existing `moon_info` / `moon_series` retain Skyfield in Python. The production
`astronomy.py` file is unchanged from HEAD. Existing solar, horizontal-position,
deep-sky-window and generic target recommendation implementations retain their
behavior. The shared deep-sky preflight only gained a caller-supplied maximum;
its existing default remains 10080. Generic `targets.recommend` still does not
invoke live astronomy.

## Model, equality and migration evidence

The Python port follows SunCalc revision
`6d90175bd11cfddbb6a9e53dd317da867eecd51b`, including operation ordering, vector and
matrix conventions, lunar terms, Sun direction, Julian/sidereal calculations,
refraction, truncating illumination, and the existing quadratic search.
The rejected Skyfield formulas remain test-only reference evidence, preserving
the inherited model-divergence assertions instead of deleting them.

On this Apple Silicon validation host, **284 intervals / 4255 samples** produced
zero measured differences in altitude, azimuth, phase, illumination and event
seconds, with exact event presence and flags. Coverage includes 2000–2049,
northern/southern polar and ordinary locations, near zenith, phase/azimuth wraps,
second-by-second event boundaries, zero/inverted intervals, non-divisible cadence,
and forward search past the final input instant. This is measured coverage, not
an all-input or cross-platform floating-point proof.

Public ceilings remain 0.5° altitude, cyclic 2° azimuth, cyclic 0.002 phase,
integer illumination ±1, and event ±60 seconds, with exact booleans/null presence
and sample times. Dedicated port regression assertions are tighter: <1e-8°
altitude, <1e-6° azimuth, <1e-12 phase, exact illumination and whole-second events.
The 83-night current same-model composition sweep preserves recommendation
scores/reasons/windows within the deterministic contract. Exact recommendation
parity remains conditioned on one frozen observation; arbitrary alternative
providers can straddle strict thresholds.

Migration-equivalence coverage includes **2395 frozen provider comparisons**:
180 inherited cases, 2024 independent phase × illumination × weather × alwaysDown
cases, 145 visibility/direction/set/null-azimuth cases, and 46 hourly-overlap and
useful-window boundary cases. A separate live-provider smoke comparison and the
original production Moon tests also pass. No existing test expectations were
weakened to accommodate a production change.

## Resource and packaging checks

Public observation inputs use whole-second UTC timestamps in 2000–2049; cadence
is integral 1...93600 seconds, positive night span <=93600 seconds, sample rows
<=1440 including the explicit endpoint. The shared ULP-aware preflight is
conservative, not an exact iteration-count characterization, and runs before
sampling. Rise/set requires at most 30 height evaluations. Recommendation
samples and ratings each cap at 1440 before row iteration, with strictly ordered
sample timestamps, finite numbers, rejected numeric booleans and strict nested
shapes. Recommendation timestamps retain the existing deep-sky 2000–2499 range.

Canonical `moon-recommendation.json` matches Python loading, the generated Swift
resource, an explicit bundle-script destination, and all 15 checked iOS build
resource copies. SHA-256:
`7dc2c35c4c342419f3318ab638d7e9b976a7edf9d92f2239a583acae8af09ceb`.
The locally built Python wheel contains the lunar modules plus LICENSE-SunCalc
and NOTICE-SunCalc. Canonical data remains externally supplied through the
existing contracts/data architecture; no conflicting package-local calibration
copy was introduced. Existing deterministic missing-data/load failure paths are
preserved, and the bundle script requires the new calibration file.

## Executed validation

All final commands below succeeded. Existing Skyfield/NumPy deprecation warnings
occur in the unchanged astronomy suites (88 Python, 44 parity warnings).

| Command | Result |
|---|---|
| `swift test --package-path packages/astro-engine-swift` | 299 passed, zero failures |
| `packages/astro-engine-python/.venv/bin/python -m pytest packages/astro-engine-python/tests` | 622 passed |
| `PYTHON=packages/astro-engine-python/.venv/bin/python scripts/parity -q -s` | 317 passed; full deterministic/live parity |
| `swift test --package-path packages/astro-engine-swift --filter Moon` | 34 passed |
| `PYTHONPATH=packages/astro-engine-python/src packages/astro-engine-python/.venv/bin/python -m pytest packages/astro-engine-python/tests/test_moon_observation.py packages/astro-engine-python/tests/test_moon_recommendation.py -q` | 77 passed before the final additional no-Skyfield regression; final full Python suite includes that regression |
| `PYTHONPATH=packages/astro-engine-python/src packages/astro-engine-python/.venv/bin/python -m pytest Tests/parity/test_moon_model.py -q -s` | 4 passed before adding nine comparator-boundary cases; final parity suite includes all 13 |
| `scripts/bundle-engine-data --host-only --destination /tmp/lunar-bundled-data` | passed; canonical bytes verified |
| `packages/astro-engine-python/.venv/bin/python -m pip wheel --no-deps ./packages/astro-engine-python -w /tmp/lunar-wheel` | built and inspected successfully |
| `git diff --check` | passed |

Focused iOS command: **17 passed** (7 migration, 10 original production Moon):

```sh
xcodebuild -project apps/ios/AstroViewingConditions.xcodeproj \
  -scheme AstroViewingConditions -configuration Debug \
  -destination 'platform=iOS Simulator,id=33CCDEE7-0A7F-4792-BCD0-6DE6077B8DC6' \
  -only-testing:AstroViewingConditionsTests/MoonRecommendationMigrationTests \
  -only-testing:AstroViewingConditionsTests/MoonRecommendationTests test
```

Full iOS command: **1329 passed**, zero failures:

```sh
xcodebuild -project apps/ios/AstroViewingConditions.xcodeproj \
  -scheme AstroViewingConditions -configuration Debug \
  -destination 'platform=iOS Simulator,id=33CCDEE7-0A7F-4792-BCD0-6DE6077B8DC6' test
```

The first sandboxed Swift build could not access system module caches; authorized
execution succeeded. An intermediate newly added Swift test syntax error and a
Moon event-comparator input-range error were corrected before final validation.
The first wheel attempt lacked setuptools with build isolation disabled; normal
isolated wheel construction succeeded. No unresolved test/build failures remain.

## Repository state

The validated lunar slice was committed as
`edc2b430588e0f4535ea29e8737e58085dd1ca4f` on
`feature/astro-engine-cli`.

No PR, release, or version bump was made as part of this slice. The temporary
untracked wheel build directory used during validation was removed. New files
outside the inherited list are the Python SunCalc port and license notices,
test-only Skyfield reference/adversarial tests, and this review report.

# Contract changelog

## 1.0.0

- Night forecast-window slice (unreleased): add
  `night_forecast.derive_window`, the exact Foundation-compatible projection of
  current astronomical dusk and following astronomical dawn wall-clock
  hour/minute onto the observing local day and its next calendar day. The host
  injects the authoritative timezone and Sun-event facts; ordinary forecast
  filtering remains half-open host composition, and cloud-timing classification
  remains deferred. Swift production now delegates its existing range derivation
  to the shared implementation under an independent migration-equivalence oracle.
  Strict transport, manual calendar/DST fixtures (including partial-hour,
  multi-hour, late-day and post-transition field-search counterexamples) and
  exact Swift/Python equality take the public catalog to 31 IDs. The version
  remains unreleased `1.0.0`; no
  existing capability or user-visible behavior changes. See
  [night forecast window](procedures/night-forecast-window.md).

- Planet observation and recommendation slice (unreleased): add
  `astronomy.planet_observation` (live night-scoped planet facts: geometric
  altitude, azimuth and geocentric solar elongation for Venus, Mars, Jupiter or
  Saturn at the production 900 s cadence, sampled by repeated addition from two
  hours before astronomical-night start while the instant stays at or before one
  hour after its end — the lead endpoint is always sampled, the trailing endpoint
  only when the cadence lands on it, and there is no explicit interval-end
  sample) and `targets.planet_recommendation`
  (deterministic visibility window, integer score and objective reason codes from
  injected observation samples, hourly ratings and a cloud-cover score).
  Production `DefaultPlanetTargetRecommendationProvider` and
  `LowPrecisionPlanetAstronomyProvider` now delegate their astronomy and
  window/score/reason math to the shared implementation, with a
  migration-equivalence sweep against verbatim copies of the pre-migration code;
  the English summary, the poor-conditions branches and the validation logging
  stay host-side. The astronomy model is unchanged and deliberately *not* an
  ephemeris: Schlyter low-precision orbital elements with the `JD - 2451543.5`
  day number, one eccentric-anomaly correction term, Earth's elements supplying
  the geocentric Sun vector, no refraction, parallax or light-time, and the
  planet path's own unclamped `asin` and `degrees(atan2(...)) + 180` azimuth
  rather than the deep-sky conversion. New calibration file
  `contracts/data/calibration/planet-recommendation.json` holds the 45/30/12/13
  weights, the inclusive 8 degree visible altitude, the 70 degree normalization,
  the 18 point low-altitude penalty, the fixed 900 s end-of-run window extension,
  the ordered convenience bands and the Venus twilight terms; the production
  debug breakdown reads that same file rather than keeping its own copies.
  `astronomy.planet_observation` bounds its night interval at 26 hours, requires
  an integral cadence and caps sampling at 1440 samples over the lead/trail span
  (`sample_cap`), reusing the conservative `targets.deep_sky_windows` preflight;
  `targets.planet_recommendation` caps each injected array at 1440 rows and
  requires strictly ordered sample instants. Its `night_start` / `night_end`
  keep the unspilled 2000...2499 range, while injected sample instants
  (`-7200 / +3600`), injected rating instants (`-10800 / +4500`) and emitted
  window instants (`-7200 / +4500`) carry a bounded spill derived from the
  observation lead/trail, the 3600 s rating hour and the fixed 900 s final-sample
  window extension — so a valid `astronomy.planet_observation` bundle for the
  earliest supported night, whose samples begin at 1999-12-31T22:00:00Z, is
  consumable verbatim on both hosts. One second outside any of those bounds still
  fails closed. One new equality comparator,
  `cyclic_azimuth_abs_0_01`, compares planet azimuth across north at a tenth of
  the lunar ceiling. Swift and Python agree bit-for-bit across the adversarial
  sweep (0.0 worst difference on altitude, azimuth and solar elongation over
  25,175 samples in 394 intervals), so the public ceilings exist only for
  cross-platform libm ULPs. `targets.planet_recommendation` carries
  `requires_injected`, like `targets.moon_recommendation`: its exact parity is
  conditioned on the injected facts, because every decision is a strict
  cut-point. Planets are deliberately not routed through `targets.recommend`, and
  `earth` is accepted by the host mapping only as an artifact of the orbital
  model — the capability rejects it, as it does Mercury, Uranus and Neptune.
  27 public IDs; new rows use `since: "1.0.0"` and fixtures `>=1.0.0 <2.0.0`. No
  version bump, no release, and no change to any existing capability's numbers.
  See [planet observation](procedures/planet-observation.md) and
  [planet recommendation](procedures/planet-recommendation.md).

- Lunar observation and recommendation slice (unreleased): add
  `astronomy.moon_observation` (live night-scoped lunar facts: continuous phase
  and integer illuminated percent at the interval midpoint, rise/set and
  always-up/always-down over `max(span, cadence)`, and geocentric refracted
  altitude/azimuth samples at the production 1800 s cadence plus an explicit
  interval-end sample) and `targets.moon_recommendation` (deterministic
  visibility window, integer score and objective reason codes from an injected
  observation, an optional already-selected best conditions window, hourly
  ratings and a cloud-cover score). Production
  `DefaultMoonTargetRecommendationProvider` now delegates its window/score/reason
  math to the shared implementation, with a migration-equivalence sweep against
  the pre-migration code; the English summary, phase names and emoji stay
  host-side. The Moon model is unchanged: geocentric, SunCalc refraction, no
  topocentric parallax, `trunc(fraction * 100)` illumination. Rise/set keep the
  production `asin(R_earth/r) - refraction_at_horizon - asin(R_moon/r)` threshold
  and hourly quadratic search, which is a different threshold from the `> 0`
  sample visibility rule. New calibration file
  `contracts/data/calibration/moon-recommendation.json` holds the 45/30/25
  weights, the near-new-Moon cap and the phase-quality tiers.
  `astronomy.moon_observation` bounds its interval and integral cadence at 26 hours
  and caps sampling at 1440 samples including the explicit endpoint (`sample_cap`),
  reusing the conservative `targets.deep_sky_windows` preflight with its own maximum; `targets.moon_recommendation` caps each
  injected array at 1440 rows. Two new equality comparators, `cyclic_phase_abs_0_002`
  and `cyclic_azimuth_abs_2`, compare quantities that wrap; `boolean_exact`
  refuses a JSON `1` for a boolean. `targets.moon_recommendation` carries
  `requires_injected`, like `night_conditions.analyze`: its exact parity is
  conditioned on the injected facts. The lunar observation is an external
  provider fact, and each host deriving its own from its own ephemeris is
  explicitly **not** an exact-parity path — every recommendation decision is a
  strict cut-point, so two ephemerides that differ at all can land on opposite
  sides of one, which no tolerance value can prevent. The vulnerable cut-points,
  the measured evidence and the single-canonical-observation product rule are
  normative in the procedure; `Tests/parity/test_moon.py` characterizes the
  rejected Skyfield composition alongside the current same-model composition.
  Python now ports the pinned production SunCalc lunar model: the inherited
  Skyfield observation failed near-zenith azimuth and event presence/flag parity.
  `moon_info` and `moon_series` retain their existing models unchanged.
  The portable Swift observation uses UTC; the production host keeps its original
  timezone convention. A Moon-specific event comparator supports bounded forward
  spill into early 2050 without widening the input timestamp range.
  25 public IDs; new rows use `since: "1.0.0"`
  and fixtures `>=1.0.0 <2.0.0`. No version bump, no release, no change to any
  existing capability's numbers, and `targets.recommend` still does not call
  astronomy. See [lunar observation](procedures/moon-observation.md) and
  [lunar recommendation](procedures/moon-recommendation.md).

- Deep-sky observation facts slice (unreleased): add
  `astronomy.horizontal_position` (closed-form geometric equatorial→horizontal at
  one instant, no ephemeris provider and no refraction) and
  `targets.deep_sky_windows` (sampling, inclusive `>=` altitude threshold,
  contiguous visible runs, interpolated interior crossings, per-run earliest-wins
  best sample, 8-point compass code). Production
  `DeepSkyTargetPositionProvider` now delegates to the shared implementation, with
  a migration-equivalence sweep against the pre-migration math. Canonical RA/Dec
  in `contracts/data/catalog/deep-sky.json` are unchanged and remain
  authoritative. Both capabilities accept timestamps only in the fixed modern
  product range `2000-01-01T00:00:00Z`–`2499-12-31T23:59:59Z` inclusive, which
  keeps the accepted domain unambiguous across Foundation and Python calendars;
  no other capability's timestamp contract changes.
  `targets.deep_sky_windows` transport also caps sampling work at 10 080 samples
  (`sample_cap`), mirroring `location.grid`'s point cap in shape and placement;
  the typed sampling APIs stay uncapped. The preflight bounds the smallest step
  repeated binary64 addition can realize, not the mathematical `span / interval`
  quotient. It is a conservative one-directional guarantee: every accepted request
  executes at most 10 080 samples, and near-cap inputs may be rejected even when
  their actual loop would have fit. Production cadences sit far inside the bound;
  unbounded and over-cap requests now fail with `sample_cap` instead of hanging.
  23 public IDs; new rows use `since: "1.0.0"` and fixtures
  `>=1.0.0 <2.0.0`. No version bump, no release, no scoring change, and
  `targets.recommend` still does not call astronomy. See
  [deep-sky observation](procedures/deep-sky-observation.md).

- Target metadata slice (unreleased): add `targets.requirements`,
  `catalog.solar_system`, and `targets.moon_sensitivity`; canonical requirement
  records/solar candidates and shared production resolvers. 21 public IDs;
  no version bump, scoring change, or live astronomy. See
  [target metadata](procedures/target-metadata.md).

- Phase 12: declare Astro Engine 1.0.0 for the frozen scoring and decode
  allow-list. No capability additions, no semantic changes, no fixture-range
  rewrites. Capability `since` values remain `0.1.0`.
- Phase 14: add `location.compare` (injected suitability) as further
  unreleased 1.0 work. Engine identity stays `1.0.0`. Capability `since`
  is `1.0.0` (introduced now; not backdated to 0.1.0). No second release.
  Compare fixtures use applicability `>=1.0.0 <2.0.0`. Suitability overlay
  is an array of `{key, suitability}` entries.

- Phase 15: add deterministic `targets.recommend` and `equipment.match`, their
  normative procedures, manual fixtures, exact equality and Swift/Python ports.
  Bind canonical target scoring and equipment preferences; reuse engine rules in
  Apple hosts without changing live providers or English copy. Both capabilities
  have `since: "1.0.0"`, fixtures `>=1.0.0 <2.0.0`. Identity remains unreleased
  `1.0.0`; existing versions, since values and fixture ranges are unchanged.

- Phase 16: add `astronomy.sun_events`, `astronomy.moon_info`, and
  `astronomy.moon_series` with a normative UTC/altitude procedure, explicit
  missing-event semantics, per-field symmetric tolerances and manual semantic
  cases. Swift reuses package-owned SunCalc; Python uses pinned Skyfield and
  locally installed DE421. Both dispatchers and the CLI expose the new IDs.
  Apple host search defaults, fallback and presentation are preserved; frozen
  scoring fixtures remain exact and injected. Planets/live target windows are
  deferred. New rows use since `1.0.0`, cases `>=1.0.0 <2.0.0`; this remains
  unreleased first-1.0 work, without a version bump or release declaration.

## 0.1.0

- F1: `observing_quality.assess` plus OQ fixtures and calibration.
- Phase 1: night-conditions analyze/score, fog/seeing/transparency procedures and
  fixtures, catalog JSON, LP identity, `json-profile.md`, parked
  `target-scoring.json` numbers (no target-scoring capability yet). Engine version stays
  `0.1.0` until Phase 12.
- Phase 6: additional hand-authored `night_conditions.analyze` fixtures
  (fog-heavy, wind penalty, transparency-only, improving trend, extra moon
  ignored, window-boundary clip). No engine-semver bump; scoring semantics
  unchanged.

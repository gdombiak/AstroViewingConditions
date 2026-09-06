# Contract changelog

## 1.0.0

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

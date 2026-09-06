# Contract changelog

## 1.0.0

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

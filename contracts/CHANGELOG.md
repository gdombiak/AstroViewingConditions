# Contract changelog

## 1.0.0

- Phase 12: declare Astro Engine 1.0.0 for the frozen scoring and decode
  allow-list. No capability additions, no semantic changes, no fixture-range
  rewrites. Capability `since` values remain `0.1.0`.
- Phase 14: add `location.compare` (injected suitability) as further
  unreleased 1.0 work. Engine identity stays `1.0.0`. Capability `since`
  is `1.0.0` (introduced now; not backdated to 0.1.0). No 1.1.0 release.
  Compare fixtures use applicability `>=1.0.0 <2.0.0`. Suitability overlay
  is an array of `{key, suitability}` entries.

## 0.1.0

- F1: `observing_quality.assess` plus OQ fixtures and calibration.
- Phase 1: night-conditions analyze/score, fog/seeing/transparency procedures and
  fixtures, catalog JSON, LP identity, `json-profile.md`, parked
  `target-scoring.json` numbers (no 1.1 capability). Engine version stays
  `0.1.0` until Phase 12.
- Phase 6: additional hand-authored `night_conditions.analyze` fixtures
  (fog-heavy, wind penalty, transparency-only, improving trend, extra moon
  ignored, window-boundary clip). No engine-semver bump; scoring semantics
  unchanged.

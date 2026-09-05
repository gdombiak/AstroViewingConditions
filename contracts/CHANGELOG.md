# Contract changelog

## 1.0.0

- Phase 12: declare Astro Engine 1.0.0 for the frozen scoring and decode
  allow-list. No capability additions, no semantic changes, no fixture-range
  rewrites. Capability `since` values remain `0.1.0`.

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

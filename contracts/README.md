# Astro Engine contract

Language-neutral product semantics for the dual Swift/Python engine.

**Current identity (`ENGINE_VERSION` 1.0.0):** unreleased. The catalogued
capabilities in `capabilities.yaml` are `observing_quality.assess`,
`night_conditions.analyze`, `night_conditions.score`, `fog.score`,
`seeing.penalty`, `transparency.penalty`, `light_pollution.lookup`,
`weather.decode`, `iss.decode`, `location.grid`, `location.compare`,
`catalog.deep_sky`, `targets.recommend`, `equipment.match`, `observing_window.select`, `targets.requirements`,
`catalog.solar_system`, `targets.moon_sensitivity`, `astronomy.horizontal_position`,
`targets.deep_sky_windows`, `astronomy.sun_events`, `astronomy.moon_info`,
`astronomy.moon_series`, `astronomy.moon_observation`,
`targets.moon_recommendation`, `astronomy.planet_observation`, and
`targets.planet_recommendation`. Composed agent hosts remain
later integration work. Phase 15 procedures describe
[generic frozen-window scoring](procedures/targets-recommend.md) and
[resolved-requirement equipment matching](procedures/equipment-match.md).

The public Python CLI allow-lists exactly those twenty-seven IDs. Capability
`since` records when that specification was introduced: existing 0.1.0-slice
rows keep `since: "0.1.0"`; `location.compare`, `targets.recommend`, and `equipment.match` use `since: "1.0.0"` because
they are introduced under the unreleased 1.0.0 identity. Do not invent a second
semantic release.

[Observing-window decisions](procedures/observing-window.md) consume projected scored
rows, preserve production endpoints and row-count quirks, and leave the existing
`night_conditions.analyze` DTO unchanged. This capability also uses `since: "1.0.0"`.

[Lunar observation](procedures/moon-observation.md) is the live Moon fact bundle
for one night; [lunar recommendation](procedures/moon-recommendation.md) is the
deterministic scorer that consumes it together with an already-selected best
conditions window. Both use `since: "1.0.0"`.

[Planet observation](procedures/planet-observation.md) is the live fact bundle
for one planet over one night, using the production low-precision orbital-element
model; [planet recommendation](procedures/planet-recommendation.md) is the
deterministic scorer that consumes it. Planets never route through
`targets.recommend`: production runs a dedicated altitude-heavy planet scorer
ahead of the generic one, calibrated by
`data/calibration/planet-recommendation.json`. Both use `since: "1.0.0"`.

## Versioning

- `ENGINE_VERSION` / `capabilities.yaml` `engine_semver` is the **current unreleased contract identity** (what a host reports in its runtime envelope). Current identity is `1.0.0`.
- A capability's `since` is the contract identity under which the **specification** was introduced. It stays valid in later compatible releases. Do not backdate a new row to `0.1.0` merely because 1.0.0 is still unreleased.
- `hosts` is who must implement the capability for that freeze (parity obligation).
- Fixture `meta.yaml` `engine_semver` is an **applicability range** (`>=0.1.0 <2.0.0` for original fixtures; new Phase 14/15/16 fixtures use `>=1.0.0 <2.0.0`). Promoting the engine to 1.0.0 without changing scoring semantics did **not** rewrite goldens.
- `expected.json` is the domain result (`ok` + `result` or `error`). It must not pin `engine_semver`.
- Phase 12 set the unreleased 1.0.0 identity when both evals were green for the initial allow-list.

See `docs/design/dual-implementation-astro-engine.md` and `json-profile.md`.

## Phase 16 astronomy

[Live astronomy procedure](procedures/astronomy.md) defines event thresholds,
UTC intervals, geocentric refracted Moon altitude, missing events, field-level
symmetric tolerances and Python resource ownership. The three astronomy rows
use `since: "1.0.0"`; identity and older histories are unchanged.

`fixtures/astronomy/cases.json` contains manually chosen inputs and semantic
expectations (no implementation-generated numeric goldens), with applicability
`>=1.0.0 <2.0.0`. `Tests/parity/test_astronomy.py` validates both engines against
those semantics and applies the same field policies in both directions.
Timestamp/altitude/illumination bounds are 60 seconds / 0.5 degrees / 1 integer
percentage point. Nulls and structure compare exactly. Existing 141 frozen
capability fixtures continue independently against their expected.json files;
none consume live astronomy. Live-provider equality remains forbidden.

Target metadata: `targets.requirements`, `catalog.solar_system`, and
`targets.moon_sensitivity` share production data and minimal procedures. See
[the normative boundary and precedence](procedures/target-metadata.md).

Mixed-target composition: `targets.compose_recommendations` turns already-scored
deep-sky, Moon and planet candidates into the production global ranking and
truncates it. It is the only mixed-target capability and makes no scoring
decision. See [the composition procedure](procedures/compose-recommendations.md).
Public capability count is 28; version remains unreleased 1.0.0.

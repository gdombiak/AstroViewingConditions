# Astro Engine contract

Language-neutral product semantics for the dual Swift/Python engine.

**Current release (`ENGINE_VERSION` 1.0.0):** the eleven catalogued 1.0
capabilities in `capabilities.yaml` (`observing_quality.assess`,
`night_conditions.analyze`, `night_conditions.score`, `fog.score`,
`seeing.penalty`, `transparency.penalty`, `light_pollution.lookup`,
`weather.decode`, `iss.decode`, `location.grid`, `catalog.deep_sky`).
Live astronomy, location.compare, and composed agent hosts remain 1.1.
Parked 1.1 numeric calibration may exist under `contracts/data` without a
capability row (target scoring).

The public Python CLI allow-lists exactly those eleven IDs. Capability
`since: "0.1.0"` records when each specification was introduced; it is not
the current engine release.

## Versioning

- `ENGINE_VERSION` / `capabilities.yaml` `engine_semver` is the **current** contract release (what a host reports in its runtime envelope). Current release is `1.0.0`.
- A capability's `since` is the contract release in which the **specification** was introduced. It stays valid in later compatible releases. 1.0 capabilities keep `since: "0.1.0"`.
- `hosts` is who must implement the capability for that freeze (parity obligation).
- Fixture `meta.yaml` `engine_semver` is an **applicability range** (currently `>=0.1.0 <2.0.0`). Promoting the engine to 1.0.0 without changing scoring semantics did **not** rewrite goldens.
- `expected.json` is the domain result (`ok` + `result` or `error`). It must not pin `engine_semver`.
- 1.0.0 was declared in Phase 12 when both evals were green for the frozen 1.0 allow-list.

See `docs/design/dual-implementation-astro-engine.md` and `json-profile.md`.

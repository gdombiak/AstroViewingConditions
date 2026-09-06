# Astro Engine contract

Language-neutral product semantics for the dual Swift/Python engine.

**Current identity (`ENGINE_VERSION` 1.0.0):** unreleased. The catalogued
capabilities in `capabilities.yaml` are `observing_quality.assess`,
`night_conditions.analyze`, `night_conditions.score`, `fog.score`,
`seeing.penalty`, `transparency.penalty`, `light_pollution.lookup`,
`weather.decode`, `iss.decode`, `location.grid`, `location.compare`,
`catalog.deep_sky`. Live astronomy, targets/equipment, and composed agent
hosts are still later work. Parked target-scoring numbers may exist under
`contracts/data` without a capability row.

The public Python CLI allow-lists exactly those twelve IDs. Capability
`since` records when that specification was introduced: existing 0.1.0-slice
rows keep `since: "0.1.0"`; `location.compare` uses `since: "1.0.0"` because
it is introduced under the unreleased 1.0.0 identity. Do not invent a second
semantic release.

## Versioning

- `ENGINE_VERSION` / `capabilities.yaml` `engine_semver` is the **current unreleased contract identity** (what a host reports in its runtime envelope). Current identity is `1.0.0`.
- A capability's `since` is the contract identity under which the **specification** was introduced. It stays valid in later compatible releases. Do not backdate a new row to `0.1.0` merely because 1.0.0 is still unreleased.
- `hosts` is who must implement the capability for that freeze (parity obligation).
- Fixture `meta.yaml` `engine_semver` is an **applicability range** (currently `>=0.1.0 <2.0.0`). Promoting the engine to 1.0.0 without changing scoring semantics did **not** rewrite goldens.
- `expected.json` is the domain result (`ok` + `result` or `error`). It must not pin `engine_semver`.
- Phase 12 set the unreleased 1.0.0 identity when both evals were green for the initial allow-list.

See `docs/design/dual-implementation-astro-engine.md` and `json-profile.md`.

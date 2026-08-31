# Astro Engine contract

Language-neutral product semantics for the dual Swift/Python engine.

**Current slice (`ENGINE_VERSION` 0.1.0):** scoring capabilities listed in
`capabilities.yaml` (`observing_quality.assess`, `night_conditions.analyze`,
`night_conditions.score`, `fog.score`, `seeing.penalty`,
`transparency.penalty`). Decode, grid, and live astronomy are later phases.
Parked 1.1 numeric calibration may exist under `contracts/data` without a
capability row (target scoring).

iOS still uses Swift literals for scoring. `capabilities.yaml` is the target
host/parity matrix for the eventual freeze, not a live implementation
inventory. A listed `hosts: [ios, cli]` row does **not** mean the CLI already
implements that capability on this branch. CLI allow-list and Python coverage
grow in later phases; F2 still allow-lists `observing_quality.assess` only.

## Versioning

- `ENGINE_VERSION` / `capabilities.yaml` `engine_semver` is the **current** contract release (what a host reports in its runtime envelope). Remains `0.1.0` until Phase 12.
- A capability's `since` is the contract release in which the **specification** was introduced. It stays valid in later compatible releases. It is not “both hosts already ship it.”
- `hosts` is who must implement the capability for that freeze (parity obligation), not who already does on the current branch.
- Fixture `meta.yaml` `engine_semver` is an **applicability range** (currently `>=0.1.0 <2.0.0`). Promoting the engine to 1.0.0 without changing scoring semantics does **not** require rewriting goldens.
- `expected.json` is the domain result (`ok` + `result` or `error`). It must not pin `engine_semver`.
- 1.0.0 is declared in Phase 12 when both evals are green. This pre-1.0 catalog may accumulate specifications before implementations catch up.

See `docs/design/dual-implementation-astro-engine.md` and `json-profile.md`.

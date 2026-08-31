# Astro Engine contract

Language-neutral product semantics for the dual Swift/Python engine.

**Current slice (`ENGINE_VERSION` 0.1.0):** `observing_quality.assess` only.

iOS still uses Swift literals for scoring. Implementations must not treat this tree as optional once a capability is listed in `capabilities.yaml`.

## Versioning

- `ENGINE_VERSION` / `capabilities.yaml` `engine_semver` is the **current** contract release (what a host reports in its runtime envelope).
- A capability's `since` is when it was introduced. It stays valid in later compatible releases.
- Fixture `meta.yaml` `engine_semver` is an **applicability range** (currently `>=0.1.0 <2.0.0` for OQ). Promoting the engine to 1.0.0 without changing OQ semantics does **not** require rewriting goldens.
- `expected.json` is the domain result (`ok` + `result`). It must not pin `engine_semver`.

See `docs/design/dual-implementation-astro-engine.md`.

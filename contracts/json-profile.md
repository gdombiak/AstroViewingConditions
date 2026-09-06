# JSON profile

Parity compares **parsed JSON** plus `equality-policy.yaml`, not document bytes.

On-disk fixtures are pretty-printed (2-space indent, trailing newline) for review.

## Required encode rules

| Rule | Why |
|---|---|
| UTF-8, no BOM | Interop |
| Finite numbers only; reject `NaN` / `±Inf` | Invalid / non-portable JSON |
| Dates as ISO-8601 UTC `YYYY-MM-DDTHH:MM:SSZ` (integer seconds, always `Z`) | Swift `JSONEncoder` default is not ISO-8601 |
| `null` vs omitted is distinct | OQ `light_pollution: null`; empty-night half-scores; omitted seeing/transparency |
| Extra keys fail | Drift detection |
| `location.compare` keys: lexicographic UTF-8 bytes | Cross-language total order; not locale collation and not Swift canonical equivalence |
| `location.compare` suitability overlay is an array of `{key, suitability}` | JSON object keys are not portable: `[String: Any]` collapses canonically equivalent identities |

Do **not** treat RFC 8785, UTF-16 key order, or “integers must encode without `.0`” as pass/fail rules.

`expected.json` is the domain result (`ok`, `capability`, `result` or `error`). It must not pin `engine_semver`.

## Phase 15 injected facts

`targets.recommend` and `equipment.match` use the existing UTC-second and finite
JSON rules. Their numeric transport inputs additionally have absolute value <=1e9
(booleans are not numbers). Instrument/candidate keys are nonempty strings with
UTF-8 identity; arrays avoid Unicode-normalizing object-key maps. Equipment's
last ordering key is UTF-8 byte order; complete target score/time ties retain
input order. Output extra/missing fields fail equality; unknown injected input
fields are ignored. Required/optional/null distinctions and enum wire values are
specified in the [target](procedures/targets-recommend.md) and
[equipment](procedures/equipment-match.md) procedures.

# targets.recommend — normative frozen-window scoring

Introduced under **unreleased 1.0.0**, not a second release. Canonical numeric data:
`data/calibration/target-scoring.json`. This procedure specifies the generic
`DefaultTargetRecommendationScorer` behavior, including the model constructor's
normalization. Neither Swift nor Python is the oracle; fixtures are worked product
examples of this procedure.

## Boundary and JSON

Use the normal capability envelope with `capability: "targets.recommend"` and an
`injected` object. No clock, time zone, provider, coordinates, ephemerides or live
alt/az are required. The input consists of:

| Field | Required value |
|---|---|
| `darkness_window` | Object with `start`, `end` UTC instants |
| `cloud_cover_score` | Numeric fallback cloud score |
| `moon` | Object with numeric `altitude` in degrees and integer `illumination` in percent |
| `hourly_ratings` | Array of `{time, score}`; scores use the existing lower-is-better 0–2 scale |
| `candidates` | Ordered array described below |
| `limit` | Optional nonnegative integer, default 5; null is invalid |

Each candidate has a unique, nonempty caller-supplied `key`, required `type`,
required numeric `difficulty`, optional/null `object_type` and `sensitivity`, and
required `window`. Type values are `deepSky`, `meteorShower`, `satellite`, `moon`,
`planet`. Object types are `galaxy`, `diffuseNebula`, `globularCluster`,
`openCluster`, `doubleStar`, `planetaryNebula`. These are wire enum values, not
English display names. A window has `start`, `end`, `best_time`, and optional/null
numeric `max_altitude` in degrees. A candidate is one target/window combination;
multiple windows for one target use distinct keys. No implementation-generated
window IDs enter the contract.

All instants follow the existing exact `YYYY-MM-DDTHH:MM:SSZ` profile. All numeric
inputs must be JSON numbers, finite and in [-1e9, 1e9], with booleans rejected.
This transport bound keeps finite aggregation arithmetic safe within the existing
1 MiB envelope; it is not an astronomical eligibility rule. Null is allowed only
for explicitly optional fields. Unknown additional object fields are ignored.
Keys compare by identity of their UTF-8 bytes without Unicode normalization.
Empty arrays are valid. Validate all candidates even for limit zero.

A zero/reversed window is accepted: its darkness overlap is zero. A reversed
astronomical night similarly contributes zero. `best_time` is a frozen ordering
fact; this capability does not recompute or constrain it to the window.

Success result: `{"recommendations": [{"key": "...", "score": 0}]}` in ranking
order. Only the integer score and candidate identity are produced; the host
retains its original windows and metadata using the key. Errors for invalid
Phase 15 injected facts have code `validation` and message
`invalid targets.recommend input`. Existing envelope/ref validation remains shared.

## Procedure

Use IEEE-754 binary64 operations in the stated order, ordinary left-to-right
sums (not compensated sums), and the numeric calibration. Here `clamp01(x)` is
`min(max(x, 0), 1)`.

1. Normalize difficulty to [0, 1], as `ObservableTarget.init` does. Normalize
   explicit sensitivity to [0, 1.5], or use the calibration default 1 when absent.
2. Altitude component is `clamp01((max_altitude ?? 0) / 80) * 30`.
3. Darkness overlap is intersection duration divided by the entire window
   duration, or zero when either the window or intersection has nonpositive
   duration. Deep sky/meteor shower component is `overlap * 35`; satellite is
   `12 + overlap * 8`; Moon/planet is `18 + overlap * 10`.
   **Darkness is not an eligibility requirement**: no candidates are removed.
4. Select hourly ratings where `time + 3600 > window.start` and
   `time < window.end`. Boundary touching alone is excluded. Each selected
   hour has equal weight even if only one second overlaps. Do not sort,
   interpolate, deduplicate or time-weight ratings. If any overlap, weather
   quality is `1 - clamp01((sum(scores) / count) / 2)`. Otherwise it is
   `1 - clamp01(cloud_cover_score / 100)`. Weather component is quality times 35.
5. Moon at/below 0 degrees produces no penalty. Otherwise interference is
   `clamp01(illumination / 100) * (0.5 + clamp01(altitude / 90) * 0.5)`.
   Multiply by the ceiling below, then by normalized sensitivity **only for
   deep sky**. Illumination is the injected integer; it is not resampled during
   the window. The "ceiling" is a base coefficient: sensitivity can exceed 1.

   | Type | Ceiling |
   |---|---:|
   | Galaxy / diffuse nebula | 55 |
   | Globular / open cluster / missing deep-sky subtype | 28 |
   | Double star | 5 |
   | Planetary nebula | 22 |
   | Meteor shower | 28 |
   | Planet | 6 |
   | Satellite | 4 |
   | Moon | 0 |

6. Difficulty penalty is normalized difficulty times 8. Evaluate
   `altitudeComponent + darknessComponent + weatherComponent - moonPenalty - difficultyPenalty`.
   Clamp to [0, 100], then round to nearest integer, exact halves away from zero.
   Do not truncate, use banker's rounding, or add 0.5 in a way that rounds a
   binary64 value just below a half prematurely.
7. Sort by integer score descending, then best-time ascending. Complete ties
   retain input order. Apply limit **after** sorting. There is no alphabetical
   target-key tie-break and no deduplication by target ID.

## Host responsibilities and production findings

The production service gives Moon and planet providers a first chance to return
specialized recommendations, falling back to the generic scorer when they do not.
Those providers, their sampling and their scores are outside this capability.
The enum values here preserve existing generic calibration; they do not promise
live Moon/planet recommendation equivalence. Production service composition and
its final sorting remain intact through engine reuse.

`DefaultTargetCatalogProvider` already resolves deep-sky sensitivity: non-nebula
and missing surface brightness use 1; planetary nebula surface brightness <=10
uses .65, >=13 uses 1.2, otherwise 1. These existing values remain canonical and
are bound into the Swift host. This capability accepts the resolved sensitivity,
not surface brightness or a catalog lookup.

Direction, azimuth, target names, images, explanation/reason copy and summary
policy are host concerns. The engine returns typed intermediate scoring facts
for unchanged host explanation generation, but these floats and English copy
are not contract equality fields. Existing window/weather/Moon fact producers
are untouched; no Phase 16 dependency is added.

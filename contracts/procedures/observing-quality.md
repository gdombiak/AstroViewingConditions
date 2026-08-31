# Observing quality (`observing_quality.assess`)

Normative procedure for `observing_quality.assess` (introduced in engine 0.1.0;
compatible through 1.x until a major semantic break). Numbers live in
`contracts/data/calibration/observing-quality.json`. This text is the
authoring spec for `expected.json`; it is not a third runtime.

There is **no second Moon term**. Moon is already in the night-conditions score.
Invalid or missing brightness is **not** treated as pristine skies.

## Inputs

- `night_conditions_score`: integer (clamped to `[score_min, score_max]`, currently 0…100)
- `modeled_zenith_sky_brightness`: JSON `null` or a finite number in mag/arcsec²

## Algorithm

```
clampedNight = clamp(night_conditions_score, score_min, score_max)

if brightness is null
   or not finite
   or brightness < plausible_brightness.min
   or brightness > plausible_brightness.max:
    return {
      score: clampedNight,
      night_conditions_score: clampedNight,
      light_pollution: null
    }

base = piecewise_linear(brightness, base_penalty_anchors)   # x = brightness
weight = piecewise_linear(clampedNight, usability_weight_anchors)  # x = night score
applied = base * weight
raw = clampedNight - applied
score = clamp(round_half_away_from_zero(raw), score_min, score_max)

return {
  score: score,                          # integer
  night_conditions_score: clampedNight,  # integer
  light_pollution: {
    modeled_zenith_sky_brightness: brightness,
    base_penalty: base,
    applied_penalty: applied
  }
}
```

`round_half_away_from_zero` is Swift `Double.rounded()` / `.toNearestOrAwayFromZero`,
then conversion to `Int`. Example: `66.5 → 67`, `-1.5 → -2`. Product scores are
non-negative after clamp.

## Piecewise-linear interpolation

Anchors are sorted by `x` ascending.

- If `x <= first.x`, return `first.y` (endpoint clamp). This applies only after
  the plausible-range check; brightness `16.0` is in `[13.0, 22.5]` so it
  clamps to the first penalty `8.0`, while `12.999` is unavailable.
- If `x >= last.x`, return `last.y`. Brightness `22.5` is still plausible, so
  it clamps to the last penalty `0.0`; `22.501` is unavailable.
- Otherwise, for the unique segment `[x0, x1]` containing `x`:
  `t = (x - x0) / (x1 - x0)` and `y = y0 + t * (y1 - y0)`.
  If `x1 == x0`, return `y0`.

## Anchors

Base penalty (mag/arcsec² → points):

`(17.5, 8.0), (18.5, 7.0), (19.5, 5.0), (20.5, 3.0), (21.3, 1.0), (21.75, 0.0)`

Usability weight (night-conditions score → 0…1):

`(35, 0.00), (45, 0.25), (65, 0.75), (80, 1.00)`

Below the first usability anchor, weight is `0` (poor nights take no further
light-pollution reduction). Above the last, weight is `1` (excellent nights
apply the full base penalty).

Plausible brightness: inclusive `[13.0, 22.5]`.

## Home backyard (manual arithmetic)

Fixture `fixtures/capabilities/observing-quality/home-backyard-v1`.

- Brightness `18.5896816253662` sits between anchors `(18.5, 7.0)` and `(19.5, 5.0)`.
- `t = (18.5896816253662 − 18.5) / (19.5 − 18.5) = 0.0896816253662`
- `base_penalty = 7.0 + t × (5.0 − 7.0) = 6.820636749267599` (IEEE-754 binary64;
  abs 1e-9 vs the 1e-9 interpolated policy)
- Night score `72` sits between usability anchors `(65, 0.75)` and `(80, 1.00)`.
- `t_w = (72 − 65) / (80 − 65) = 7/15`
- `weight = 0.75 + (7/15) × 0.25 = 13/15`
- `applied = 6.820636749267599 × 13/15 = 5.911218516031919`
- `score = Int((72 − applied).rounded()) = Int(66.088….rounded()) = 66`

## Exact anchors

Fixtures `anchor-*-v1` use night-conditions score `80` so usability weight is
exactly `1`. Then `applied_penalty = base_penalty` and `score = 80 − penalty`.
Equality policy `observing_quality_anchor` (abs 1e-12 on penalties).

## Other frozen boundaries (F1)

These are independent branches a second implementation can get wrong. They are
not a combinatorial matrix.

| Fixture | What it freezes |
|---|---|
| `usability-weight-zero-night-35-v1` | Exact usability anchor 35 → weight 0. LP **present**, `applied_penalty` 0, score equals night score. Distinct from missing brightness. |
| `brightness-range-min-13-v1` | Inclusive `13.0`: in range, endpoint-clamp to penalty 8, not unavailable. |
| `brightness-range-max-22-5-v1` | Inclusive `22.5`: in range, endpoint-clamp to penalty 0, not unavailable. |
| `brightness-below-range-v1` | `12.999`: unavailable (`light_pollution` null). Not pristine, not clamped. |
| `unavailable-brightness-v1` | JSON `null` brightness: same fallback as out-of-range. |
| `night-score-clamp-high-v1` | Input 150 → clamped night 100 (null brightness isolates clamp). |
| `night-score-clamp-low-v1` | Input −5 → clamped night 0. |

`22.501` is the same out-of-range branch as `12.999` and is not a separate fixture.
JSON cannot represent NaN/Inf; those remain Swift-only unit tests until F3.

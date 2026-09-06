# Planet recommendation (unreleased 1.0)

Capability: `targets.planet_recommendation`, `since: "1.0.0"`,
`hosts: [ios, cli]`, equality `planet_recommendation`. **Deterministic**: the
observation samples, the hourly ratings and the cloud-cover score are injected,
so no ephemeris, network, location service or calendar runs here. Portable form
of the private math in the production
`DefaultPlanetTargetRecommendationProvider`.

Planets do **not** route through `targets.recommend`. Production runs a dedicated
altitude-heavy planet scorer ahead of the generic target scorer, and that
boundary is preserved: the constants live in
`contracts/data/calibration/planet-recommendation.json`, and the generic
`target-scoring.json` never applies to a planet.

## Boundary review

Audit verdict: **Agree, with corrections.** Best-sample weighting, the visible
altitude threshold, the 70-degree normalization, the Venus twilight terms and the
45/30/12/13 score weights all exist in production. Six statements needed
correction before extraction:

- **The visible-altitude filter is inclusive.** `altitude >= 8`, not `> 8`. That
  differs from the lunar rule, which is `> 0`.
- **Best-sample selection is not "highest altitude".** It maximizes
  `0.70 * clamp(altitude / 70) + 0.15 * darkness + 0.15 * convenience`, where
  darkness is `1` inside astronomical night and `0.55` outside. Swift `max(by:)`
  keeps the **earliest** element of a tie, and both hosts reproduce that.
- **The end-of-run extension is a fixed 900 s literal, not the cadence.** It
  happens to equal the default sampling cadence; it is not derived from it, and a
  caller cadence of 3600 s does not change it.
- **`astronomicalDarkness` keys on the darkness overlap, not on the visibility
  quality.** For Venus the visibility term can be raised by twilight suitability
  while the reason still does not apply.
- **The interpolation guard is `> 0.0001` degrees on the altitude change**, and
  it returns the *earlier* sample's instant unchanged. It is a structural numeric
  guard, so it stays a code constant rather than calibration.
- **The convenience bands are ordered, not disjoint.** The evening band
  `[night_start - 7200, night_start + 14400]` is tested first, so an instant that
  is also inside the late-night band `[night_end - 10800, ∞)` still scores `1`.
  A night shorter than about seven hours makes that overlap reachable.

Also preserved and deliberately not "cleaned up": the reason list always ends
with `planetMoonlightResistant`, so it is never empty and needs no fallback
entry; the weather comparison is on the *computed* double, so a rating average of
`1.1` yields `0.44999999999999996` and does trip the poor-weather reason; and the
window fields are always present, because the planet path always has a best
visible sample.

Rejected alternatives:

- **Folding planets into `targets.recommend`.** The specialized scorer exists
  deliberately in production and has different weights, a different altitude
  normalization, a different low-altitude penalty and a different reason set.
- **Deriving the 900 s extension from the injected cadence.** Production does
  not, and the injected samples need not be evenly spaced at all.
- **Moving the English summary into the contract.** The summary branches on
  presentation policy (poor conditions, "after sunset", "before dawn") and on a
  localized time formatter. It stays with the host, as it does for the Moon.

## Inputs

Object with exactly `target_id`, `night_start`, `night_end`, `samples`,
`cloud_cover_score` and `hourly_ratings`. Nothing is optional.

- `target_id`: one of `venus`, `mars`, `jupiter`, `saturn`. Only `venus` changes
  behavior; the others differ solely in identity.
- `night_start` / `night_end`: whole-second `Z` instants in
  `2000-01-01T00:00:00Z ... 2499-12-31T23:59:59Z`, the same fixed modern product
  range as `targets.deep_sky_windows` and `targets.moon_recommendation`. This is
  the **night** range and is deliberately *not* spilled: an instant inside the
  sample spill below but outside this range is still rejected here.
- `samples`: the `observation.samples` array from `astronomy.planet_observation`.
  Each row is exactly `{time, altitude, azimuth, solar_elongation}`. `time` must
  be strictly increasing — production reads the window through
  `firstIndex(where: time ==)` / `lastIndex(where: time ==)`, which has one
  meaning only for a strictly ordered series. `altitude` and `azimuth` are
  required finite numbers; `solar_elongation` may be `null` and is then read as
  `0`, exactly as production's `?? 0`.
- `cloud_cover_score`: finite number, the production `details.cloudCoverScore`.
- `hourly_ratings`: rows of exactly `{time, score}` in caller order. Production
  never sorts them, and the average is an ordered binary64 sum.

### Bounded spill on provider-derived instants

`astronomy.planet_observation` samples from `night_start - 7200` through
`night_end + 3600`, so a valid observation bundle for the earliest supported
night contains instants in 1999. A capability that rejected them could not
consume its own documented producer, so injected and emitted instants carry a
**bounded** spill around the night range. Each offset is derived from a
production constant and is a fixed transport literal, not a calibration read, so
tuning the scorer can never widen the accepted range:

| Instant | Spill | Accepted / emitted range |
|---|---|---|
| `night_start`, `night_end` | none | `2000-01-01T00:00:00Z ... 2499-12-31T23:59:59Z` |
| `samples[].time` | `-7200` (observation lead) / `+3600` (observation trail) | `1999-12-31T22:00:00Z ... 2500-01-01T00:59:59Z` |
| `hourly_ratings[].time` | `-10800` (lead + one 3600 s rating hour) / `+4500` | `1999-12-31T21:00:00Z ... 2500-01-01T01:14:59Z` |
| emitted window instants | `-7200` / `+4500` (trail + the fixed 900 s extension) | `1999-12-31T22:00:00Z ... 2500-01-01T01:14:59Z` |

The rating range is a **conservative transport envelope**, not a claim that every
accepted rating instant can overlap some window. It is the smallest absolute
range that admits every rating a valid window could consult: the floor is one
rating hour below the earliest possible window start, because a rating overlaps
when `[t, t + 3600)` reaches past `window.start`, and the ceiling is the latest
possible window end, because a rating must begin strictly before it. Both rating
extremes are in fact non-overlapping by construction — a rating exactly on the
floor ends exactly at the earliest window start, and one exactly on the ceiling
begins exactly at the latest window end — and both are still accepted.
**Overlap semantics are unchanged and remain strict**: acceptance by the
transport never implies participation in `weather_quality`, and a rating that
does not strictly overlap simply does not contribute.

The sample and emitted-window bounds are tight and reachable: the lower window
start and the upper window end are each exactly attainable. One second outside
any of these ranges fails closed.

Bounded inputs make every emitted instant provably inside the emitted range, so
the formatter never rejects a legitimate result on either host.

Resource bounds: each injected array is capped at 1440 rows, checked on the array
before it is iterated, reporting `code: "sample_cap"`. Everything else reports
`code: "validation"` with `invalid targets.planet_recommendation input`. JSON
booleans are not numbers, unknown keys anywhere fail closed, and an empty
`samples` array is accepted and yields no recommendation.

## Procedure

1. `visible = [s for s in samples if s.altitude >= 8]`. If empty, the whole
   result is `null`.
2. `best` is the visible sample maximizing
   `0.70 * clamp(altitude / 70, 0, 1) + 0.15 * darkness + 0.15 * convenience`,
   with `darkness = 1` when `night_start <= time <= night_end` and `0.55`
   otherwise. Ties keep the earliest sample.
3. Window start: if the first visible sample has a predecessor in `samples`,
   interpolate the threshold crossing between them; otherwise use the first
   visible instant. Window end: if the last visible sample has a successor,
   interpolate between them; otherwise add 900 s to the last visible instant.
   A crossing whose `|Δaltitude| <= 0.0001` returns the earlier instant.
   Interpolation is `first.time + (second.time - first.time) * clamp((8 - first.altitude) / Δ, 0, 1)`.
4. `weather_quality` is `1 - clamp(mean(overlapping ratings) / 2, 0, 1)` over the
   ratings whose `[time, time + 3600)` strictly overlaps `(window.start, window.end)`,
   and `1 - clamp(cloud_cover_score / 100, 0, 1)` when none overlap.
5. `darkness_overlap` is the fraction of the *window* inside
   `[night_start, night_end]`, and `0` for a non-positive window or a
   non-positive intersection.
6. `convenience` is `convenienceScore(best.time)` under the ordered bands above:
   `1` in the evening band, else `0.35` from `night_end - 10800` onward, else `0.65`.
7. `visibility_quality` is `darkness_overlap`, except for Venus where it is
   `max(darkness_overlap, twilight)`. Venus twilight is `0` unless
   `best.time < night_start and window.end > night_start - 7200` (evening) or
   `best.time > night_end and window.start < night_end + 7200` (morning), and is
   otherwise
   `0.45 * clamp((altitude - 8) / 12) + 0.30 * clamp(window_duration / 2700) + 0.25 * clamp((elongation - 15) / 30)`.
8. `score = round(clamp(45 * clamp(altitude / 70) + 30 * weather + 12 * visibility + 13 * convenience - penalty, 0, 100))`,
   where `penalty` is `18` when `altitude < 15` and `0` otherwise, and rounding is
   half away from zero.
9. Reasons, in this order: `highAltitude` when `altitude >= 45`, else
   `lowAltitude` when `altitude < 20`; `astronomicalDarkness` when
   `darkness_overlap >= 0.45`; `convenientPlanetWindow` when `convenience >= 0.72`,
   else `lateOrEarlyPlanetWindow` when `convenience <= 0.35`; `goodNightQuality`
   when `weather >= 0.7`, else `poorWeather` when `weather < 0.45`; then always
   `planetMoonlightResistant`.

## Output

```
recommendation: null | {
  score,
  visibility_window: { start, end, best_time, max_altitude, direction, azimuth },
  reasons: [objective code, ...]
}
```

`max_altitude`, `direction` and `azimuth` are echoed from the best sample and are
never null. `direction` is the objective sixteen-point compass code with
round-half-away-from-zero — the same code the Moon path reports, deliberately not
the eight-point deep-sky code. The host uppercases it for display, which is a
no-op on these values.

Window instants are injected instants plus interpolated offsets and are generally
not whole seconds. The engine keeps the full binary64 instant; the transport
floors to the whole second, the same way `targets.deep_sky_windows` does.

No English copy is emitted. The production summary, its poor-conditions branches
and the localized time formatting stay in the host adapter.

## Composition boundary

Exact parity is conditioned on the injected facts, exactly as it is for
`night_conditions.analyze` and `targets.moon_recommendation`. Every decision here
is a strict cut-point on a provider quantity: `altitude >= 8`, `altitude < 15`,
`altitude >= 45`, `altitude < 20`, `darkness_overlap >= 0.45`,
`weather < 0.45`, `weather >= 0.7`, `convenience >= 0.72`, `convenience <= 0.35`,
the Venus eligibility comparisons, and the integer score rounding. Two hosts that
each derive their own planet observation can land on opposite sides of one of
those, and no tolerance value prevents it.

A valid `astronomy.planet_observation` fact bundle is consumable **verbatim**
here, including at the earliest supported night where the sampling lead reaches
into 1999. That invariant is enforced by the spill bounds above and exercised by
`Tests/parity/test_planets.py::test_lower_bound_observation_result_composes_verbatim_on_both_hosts`.

Today both hosts run the same production orbital-element model, so
`Tests/parity/test_planets.py::test_same_model_composition_keeps_all_decisions`
holds across the whole composition sweep, whose boundary nights include the
earliest supported night and the latest night the observation capability accepts. That is a property of the shared model,
not of this contract. Where one answer is required, freeze one observation and
inject it into both hosts.

## Equality

Policy `planet_recommendation`. `recommendation` is `null_or_object`; `score`,
the three window instants, `direction` and the ordered `reasons` array are exact.
`max_altitude` and `azimuth` are echoed from the injected sample, so `abs_1e12`
bounds transport rounding only. Extra or missing fields fail closed.

## Out of scope

Live astronomy, mixed-target composition, equipment-aware composition, Best
Nearby and location-set scoring, multi-night forecast eligibility, active-night
semantics, availability/failure semantics, English copy, and any change to
`targets.recommend`, `targets.moon_recommendation` or `targets.deep_sky_windows`.

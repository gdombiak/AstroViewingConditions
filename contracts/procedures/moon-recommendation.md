# Lunar recommendation (unreleased 1.0)

Capability: `targets.moon_recommendation`, `since: "1.0.0"`, `hosts: [ios, cli]`,
equality `moon_recommendation`. **Deterministic**: the Moon fact bundle is
injected, so no ephemeris, catalog or network access happens here. The producer of
that bundle is `astronomy.moon_observation`.

## Boundary review

Audit lead verdict: **Partially Agree**. The dedicated 45/30/25 scorer, the
`> 0°` visibility rule, first/last visible sample semantics, the `+30 min`
extension clipped to the interval end, the visibility fraction, the useful window
taken from the already-computed best conditions window, the near-new-Moon cap and
the deterministic reasons all exist in `DefaultMoonTargetRecommendationProvider`
(apps/ios/.../MoonRecommendationService.swift). Corrections:

- **The `+30 min` extension is a literal, not the sampling cadence.** Changing
  `sampleInterval` does not change it. The end is
  `min(max(lastVisible + 1800, firstVisible + 1800), usefulWindow.end)`.
- **The visibility fraction is over the samples inside the useful window**, not
  over all night samples: a Moon that is up all night but whose best-conditions
  window is short still scores on the clipped set.
- **Weather quality is scoped to the visibility window, not the night**: hourly
  ratings whose `[time, time+3600)` overlaps the window. Only when none overlap
  does it fall back to `1 - clamp(cloudCoverScore/100)`.
- **`moonBelowUsefulWindow` is not "the Moon never rose".** It fires when the
  visible fraction is below 0.25 *or* the observation is `always_down`, and it can
  be emitted together with a phase reason.
- **Direction is the sixteen-point code**, rounded, unlike the eight-point
  truncated code of `targets.deep_sky_windows`. Both are objective codes.
- **A `nil` recommendation is a real product outcome**: with no visible sample in
  the useful window the Moon is simply not a candidate.

Not in the audit and preserved: `visibleSamples.isEmpty` is still tested inside the
reason builder although the caller already returned for that case; the empty reason
list falls back to `moonVisibleUsefulWindow`; the score is rounded half away from
zero and clamped twice (here and again by the host DTO).

Rejected alternatives:

- **Folding the Moon into `targets.recommend`.** That capability is the generic
  frozen-window scorer with altitude/darkness/weather/moon-interference terms and
  the `moon` ceiling of `0`; production never routes the Moon through it. Merging
  would either change lunar scores or add a second scoring mode to a frozen
  contract. Mixed-target composition is a later slice.
- **Reusing `targets.deep_sky_windows`.** Its threshold is inclusive at 15°, it
  interpolates interior crossings and it emits one window per run. The Moon uses a
  strict `> 0°` test, no interpolation, one window, and a fixed end extension.
- **Recomputing the best conditions window here.** `observing_window.select`
  already owns that selection; this capability consumes its result.
- **Emitting the English summary.** `hasPoorTargetRecommendationConditions` and the
  summary strings are presentation and stay on the host.

## Inputs

Object with `night_start`, `night_end`, `moon`, `cloud_cover_score`,
`hourly_ratings`, and an optional `best_window`.

- Instants are whole-second `YYYY-MM-DDTHH:MM:SSZ` values that round-trip exactly,
  from `2000-01-01T00:00:00Z` through `2499-12-31T23:59:59Z` inclusive — the same
  fixed modern product range as `targets.deep_sky_windows`, chosen for the same
  reason (the hosts disagree about pre-Gregorian-cutover calendars).
- `best_window`: `null`, omitted, or `{start, end}`. Omitted and `null` are the
  same input and mean the production `bestWindow == nil`, in which case the useful
  window is `[night_start, night_end]`. The window is used as given; it is not
  clipped to the night.
- `moon`: exactly `{phase, illumination, rise, set, always_up, always_down,
  samples}` — the `astronomy.moon_observation` result shape minus its echoed
  interval, so one host's observation can be handed to every host verbatim. That
  shape match is *not* a licence for each host to derive its own observation; see
  **Composition boundary**. `rise` and `always_up` are accepted so the whole
  bundle round-trips unchanged and do not affect the result. `phase` is a finite
  number clamped to `0...1`; `illumination` is an integral number clamped to
  `0...100`; `always_up` / `always_down` must be JSON booleans; `rise` / `set` are
  instants or `null`.
- `moon.samples`: rows of exactly `{time, altitude, azimuth}` with strictly
  increasing `time`. `azimuth` may be `null`. Order is preserved, never sorted.
- `hourly_ratings`: rows of exactly `{time, score}`, `score` the production 0–2
  hourly rating. **Caller order is preserved and the rows are not sorted**:
  production filters and sums them in assessment order, and binary64 addition is
  order-dependent.
- `cloud_cover_score`: finite number.

Resource bounds, checked before iteration: each array is capped at `1440` rows
(one day of one-minute rows). Over the cap: `code: "sample_cap"`, message
`targets.moon_recommendation exceeds the 1.0 row cap (1440 rows)`. Everything else
is `code: "validation"`, message `invalid targets.moon_recommendation input`.

## Procedure

1. `useful = best_window ?? [night_start, night_end]`.
2. `useful_samples` = samples with `useful.start <= time <= useful.end`.
   `visible` = those with `altitude > 0` — **strict**, and on the refracted
   altitude the observation reported.
3. If `visible` is empty the result is `{"recommendation": null}`.
4. `best` = the maximum-altitude visible sample; ties keep the **earliest**,
   matching Swift `max(by:)`.
5. Window: `start = max(visible.first.time, useful.start)`;
   `end = min(max(visible.last.time + 1800, visible.first.time + 1800),
   useful.end)`; `best_time = best.time`; `max_altitude = best.altitude`;
   `azimuth = best.azimuth`; `direction` is the sixteen-point code
   `["N","NNE",…,"NNW"][round(normalized_azimuth / 22.5) % 16]` with
   round-half-away-from-zero, or `null` when the azimuth is `null`.
6. `visible_fraction = |{s in useful_samples : altitude > 0}| / |useful_samples|`,
   and `0` when `useful_samples` is empty.
7. `weather_quality`: over the hourly ratings whose `time + 3600 > window.start`
   and `time < window.end`, in caller order,
   `1 - clamp(sum/count / 2, 0, 1)`; with none overlapping,
   `1 - clamp(cloud_cover_score / 100, 0, 1)`.
8. `phase_quality`: `0.12` when near new Moon (`illumination <= 8` or
   `phase <= 0.04` or `phase >= 0.96`); else `1.0` when
   `min(|phase - 0.25|, |phase - 0.75|) <= 0.08`; else `0.82` when
   `illumination <= 45`; else `0.70` when `illumination >= 90`; else `0.68`.
9. `raw = phase_quality * 45 + visible_fraction * 30 + weather_quality * 25`,
   capped at `35` when `illumination <= 8`, clamped to `0...100`, then rounded half
   away from zero to an integer.
10. Reasons, in this order, deduplicated only by construction:
    - `moonBelowUsefulWindow` when `visible` is empty, or
      `visible_fraction < 0.25`, or `always_down`;
    - then exactly one of `newMoonDarkSky` (near new Moon),
      `excellentMoonCraterDetail` (within 0.08 of a quarter),
      `brightFullMoonDeepSkyImpact` (`illumination >= 90`), or
      `moonVisibleUsefulWindow` (`visible_fraction >= 0.25`);
    - `moonSetsEarlyDarkSkyLater` when `set` exists, `set > useful.start`,
      `set < useful.end - 7200` and `illumination >= 40`;
    - `poorWeather` when `weather_quality < 0.45`.
    An empty list becomes `["moonVisibleUsefulWindow"]`.
11. Window instants are floored to the whole second on output.

Constants live in `contracts/data/calibration/moon-recommendation.json`.

## Output

```
{ "recommendation": null }
{ "recommendation": { "score": 0…100,
    "visibility_window": { "start": "…Z", "end": "…Z", "best_time": "…Z",
                           "max_altitude": deg|null, "direction": code|null,
                           "azimuth": deg|null },
    "reasons": [ code, … ] } }
```

Reason codes are the production `TargetRecommendationReason` identifiers, which are
stable objective keys; the English `message` for each stays host-side.

## Composition boundary

**Normative.** This capability's exact parity is conditioned on the injected
facts, exactly as `night_conditions.analyze`'s is on its injected `moon_series`.
The lunar observation is an *external provider fact*. Running
`astronomy.moon_observation` on each host and feeding each host's own result into
its own `targets.moon_recommendation` is **not** an exact-parity path, and the
engine does not claim it is.

The reason is structural, not a matter of tolerance size. Every decision below is
a strict cut-point on a live quantity. Two ephemerides that disagree *at all* —
by one part in 10^9, let alone by the tolerated amount — can land on opposite
sides of one, and the deterministic scorer then faithfully computes two different
correct answers from two different inputs. Tightening
`astronomy_moon_observation`'s tolerances cannot close this; only a single
canonical observation can.

Vulnerable cut-points when observations come from different provider models
(the rejected SunCalc/Skyfield pair supplies reproducible examples):

| Cut-point | Effect when straddled |
|---|---|
| `illumination <= 8` | near-new phase quality `0.12` **and** the score cap of 35, plus `newMoonDarkSky` |
| `illumination <= 45` | crescent `0.82` vs default `0.68` (6.3 score points) |
| `illumination >= 90` | bright `0.70` vs `0.68`, plus `brightFullMoonDeepSkyImpact` |
| `phase <= 0.04` / `>= 0.96` | near-new branch as above |
| `min(abs(phase-0.25), abs(phase-0.75)) <= 0.08` | quarter `1.0` vs `0.68` (14.4 score points), plus `excellentMoonCraterDetail` |
| `set < useful.end - 7200` | `moonSetsEarlyDarkSkyLater` present or absent |
| `altitude > 0` on one sample | visible set, window endpoints, visible fraction and score |

The inherited Skyfield model is now a test-only reference. Its 83-night
composition sweep still reproduces differences across illumination and early-set
thresholds. For example, 2026-03-16T02:00:00Z–11:00:00Z at 40.7N/74.0W gives
SunCalc illumination 9, score 64 and `[moonBelowUsefulWindow]`, versus Skyfield
illumination 8, score 33 and `[moonBelowUsefulWindow, newMoonDarkSky]`.
These retained assertions explain why frozen observations matter; they are not
current production Swift/Python discrepancies. The same 83-night sweep through
the production SunCalc implementations now agrees on recommendation decisions.
Other discontinuities include the earliest maximum-altitude sample, 16-point
compass rounding, and event presence/always flags. The listed sweep does not
claim to exhaust every reachable discontinuity.

**Product rule.** A single observation must reach every consumer. The host that
owns the night computes `astronomy.moon_observation` once; the Bot and any other
consumer inject that same bundle rather than re-deriving it. Where a consumer
genuinely cannot obtain the host's observation, its lunar score is an independent
estimate and must not be presented as the app's number.

## Equality

Policy `moon_recommendation`. Both hosts execute the same binary64 operations on
the same injected values, so the score and the ordered reasons compare exactly and
the instants compare exactly; echoed altitude/azimuth use `null_or_abs_1e12` for
transport rounding only. This is deliberately not the live `abs_0_5` tolerance:
nothing here is sampled. Parity fixtures therefore inject one frozen observation
into both hosts; `Tests/parity/test_moon.py` separately characterizes the rejected Skyfield composition and the current same-model composition. The
independent pre-migration Swift oracle also covers phase/illumination/weather
interactions, visibility fractions, compass, set and hourly-overlap boundaries.

## Out of scope

Planet recommendation, mixed Moon/planet/deep-sky ordering and limits, equipment
filtering, Best Nearby, multi-night composition, weather acquisition, English
summaries, phase names and emoji.

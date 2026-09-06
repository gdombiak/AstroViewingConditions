# Lunar observation facts (unreleased 1.0)

Capability: `astronomy.moon_observation`, `since: "1.0.0"`, `hosts: [ios, cli]`,
equality `astronomy_moon_observation`. **Live/provider-derived**: lunar facts are calculated for the requested night.
Both hosts use the production analytic SunCalc model; no external ephemeris file
or network is required. Existing `moon_info` / `moon_series` are unchanged. The deterministic consumer is
`targets.moon_recommendation` (contracts/procedures/moon-recommendation.md).

## Boundary review

Audit lead verdict: **Partially Agree**. Continuous phase, Moon azimuth, rise/set,
always-up/always-down, the night-midpoint phase instant and the 30-minute cadence
with an explicit interval-end sample all exist in production, in
`SunCalcMoonObservationSampler` (packages/astro-engine-swift/.../MoonObservation.swift)
driven by `SunCalcMoonAstronomyProvider`. Four statements needed correction:

- **Rise/set do not use the sample visibility rule.** Samples are "visible" at
  refracted geocentric altitude `> 0`. `MoonTimes` instead crosses the
  *unrefracted* geocentric altitude against
  `asin(R_earth/r) - refraction_at_horizon - asin(R_moon/r)` (≈ +0.125°), found by
  an hourly quadratic-interpolation search. Two different thresholds, deliberately.
- **The rise/set search window is not the night.** It is `max(nightEnd - nightStart,
  sampleInterval)` from `nightStart`, so a zero-length or inverted interval still
  searches one cadence forward.
- **`alwaysUp` can coexist with a non-nil `rise`.** The flags are seeded from the
  sign at hour 0 (`y0 > 0` sets `alwaysUp`, otherwise `alwaysDown`) and are cleared
  only by the *opposite* event.
- **The midpoint is `nightStart + max(span, 0) / 2`.** An inverted interval
  evaluates phase and illumination at `nightStart`.

Not in the audit and preserved here: the phase *name* is presentation and is not
emitted; a position-sample failure is skipped rather than failing the interval;
`MoonObservationData` clamps phase to `0...1` and illumination to `0...100`.

Rejected alternatives:

- **Extending `astronomy.moon_info` / `astronomy.moon_series` with phase, azimuth
  and rise/set.** Those capabilities are specified as instantaneous facts at
  caller-chosen instants; the observation bundle is night-scoped and owns a
  cadence, a search limit and a midpoint rule. Widening them would also change the
  meaning of their existing fixtures.
- **A "more accurate" topocentric Moon model.** Production is geocentric with
  SunCalc's refraction and no lunar parallax. Replacing it would move every
  altitude, every visibility decision and therefore every lunar score.
- **Deriving rise/set from the 30-minute samples.** Production does not; the
  hourly quadratic search resolves crossings to seconds, and the sample cadence
  would resolve them only to half an hour.

## Inputs

Object with exactly `latitude`, `longitude`, `night_start`, `night_end`, and an
optional `sample_interval_seconds`.

- `latitude` / `longitude`: finite JSON numbers in `[-90, 90]` / `[-180, 180]`.
  JSON booleans are not numbers and are rejected.
- `night_start` / `night_end`: whole-second `YYYY-MM-DDTHH:MM:SSZ` instants that
  round-trip exactly, from `2000-01-01T00:00:00Z` through `2049-12-31T23:59:59Z`
  inclusive — the same window as the rest of the `astronomy.*` namespace.
- `sample_interval_seconds`: finite integral seconds in `1...93600`; default `1800`.
  Whole seconds prevent duplicate floored timestamps and host-dependent cadence
  accumulation. Fractional cadences are rejected, not rounded.
- `night_end - night_start` must not exceed 26 hours. It **may** be negative: an
  inverted interval yields no samples and still runs the rise/set search, which is
  the production behavior.

Resource bounds, checked before any iteration:

- The conservative sample-count preflight of `targets.deep_sky_windows` is reused with a
  maximum of `1440` samples (one day of one-minute cadence; production asks for at
  most ~53). A non-divisible positive span reserves one row for the explicit
  endpoint; an exactly divisible span needs no extra row. Python uses the same
  2001 reference epoch as Swift for this preflight. It bounds the *realized* repeated-addition step, not `span/interval`,
  so a step too small to advance binary64 is rejected rather than looping. Over the
  cap: `code: "sample_cap"`, message
  `astronomy.moon_observation exceeds the 1.0 sample cap (1440 samples)`.
- Both the cadence and the positive night span are bounded at 26 hours, so
  `limit = max(span, cadence)` is bounded even for zero-length/inverted nights.
  Rise/set performs at most `ceil(limit/3600) + 4` height evaluations (30):
  three initial heights and one after each unsuccessful hourly iteration.
- The preflight is conservative, not an exact characterization of loop count.
  A non-advancing step fails with `sample_cap` before the integral-cadence check.

Any other input failure is `code: "validation"`, message
`invalid astronomy.moon_observation input`.

## Procedure

1. `midpoint = night_start + max(night_end - night_start, 0) / 2`.
2. At `midpoint`, geocentrically: `phi = pi - elongation(Moon, Sun)`,
   `fraction = (1 + cos phi) / 2`, `illumination = trunc(fraction * 100)` clamped
   to `0...100`. The signed phase is `degrees(phi) * sign`, where `sign` is the
   sign of the declination of `Moon x Sun` — equivalently the sign of
   `sin(ra_sun - ra_moon)`; negative is waxing. Report
   `phase = clamp((signed_degrees + 180) / 360, 0, 1)`, so `0` and `1` are new Moon
   and `0.5` is full.
3. Rise/set: with `limit = max(night_end - night_start, sample_interval)` and
   `h(k) = geometric_altitude(night_start + k hours) - (asin(6371.0/r) -
   refraction_at_horizon - asin(1737.1/r))`, where
   `refraction_at_horizon = pi / (tan(radians(7.31 / 4.4)) * 10800)` and `r` is the
   geocentric distance in km, walk `k = 0, 1, ...` while `k <= ceil(limit/3600)`,
   fitting the quadratic through `h(k-1), h(k), h(k+1)`. Seed
   `always_up = h(0) > 0`, `always_down = not always_up`. A single root is a rise
   when `h(k-1) < 0` and otherwise a set; with two roots the later is the rise
   when the extremum is negative. Only the first rise and first set in
   `[0, limit/3600)` are kept; a rise clears `always_down`, a set clears
   `always_up`. Stop once both are known. This is commons-suncalc's `MoonTimes`
   search, with the same production analytic lunar facts in both hosts.
4. Samples: when `night_end >= night_start`, emit a sample at `night_start` and
   then by repeated addition of `sample_interval` while `time <= night_end`; if the
   last emitted instant is not exactly `night_end`, append one more at `night_end`.
   Each sample reports the geocentric altitude with SunCalc's refraction applied
   (`+ 0.000296706 / tan(h + 0.00312537 / (h + 0.0890118))` for `h >= 0`, otherwise
   none) and the north-based azimuth in `[0, 360)`.
5. Output instants are floored to the whole second.

## Output

```
{ "night_start": "…Z", "night_end": "…Z",
  "phase": 0.0…1.0, "illumination": 0…100,
  "rise": "…Z"|null, "set": "…Z"|null,
  "always_up": bool, "always_down": bool,
  "samples": [ { "time": "…Z", "altitude": deg, "azimuth": deg|null } ] }
```

`azimuth` is nullable because the production `MoonPositionSample` type is; the
production Swift and Python samplers both always supply it.

## Equality

Policy `astronomy_moon_observation`. The public maximum tolerances remain
0.5° altitude, cyclic 2° azimuth, cyclic 0.002 phase, one integer illumination
point, and 60 seconds per event; booleans and sample instants must match exactly.
`null` matches only `null`. The Moon-specific event comparator allows the bounded
forward search to spill past the final accepted input instant into early 2050;
this does not widen the input range or the existing solar comparator.

The inherited Skyfield implementation did **not** meet this policy: at
20.517045369405356° N, 26.523419481713518° W on 2026-03-01T00:00:00Z, its
near-zenith azimuth differed from Swift by 112.217801°. For New York
(40.7, -74), 2026-08-29T00:00:00Z–11:46:30Z, Swift found a set at 11:46:28Z,
while Skyfield returned `null` and `always_up = true`. A larger angular or event
tolerance cannot reconcile null/event or boolean disagreements.

Python therefore ports the pinned production SunCalc model (revision
`6d90175bd11cfddbb6a9e53dd317da867eecd51b`) in `suncalc_moon.py`, including
vector/matrix arithmetic, UTC Julian century and sidereal time, lunar periodic
terms, the Sun direction used for illumination, and refraction. Swift's portable
entry uses UTC; the iOS entry retains its original timezone convention.
The original Skyfield formulas survive only in `Tests/parity/moon_skyfield_reference.py`
as independent counterexamples, not as a production observation provider.

The adversarial regression sweeps 284 intervals / 4255 samples over 2000–2049,
both poles, high latitudes, phase and azimuth wraps, near-zenith geometries,
second-by-second event limits, non-divisible cadence, inverted and zero-length
intervals. On the validation host, all measured deltas were zero, including
illumination and event presence/flags. Regression limits are deliberately much
tighter than the public ceilings: altitude <1e-8°, azimuth <1e-6°, phase <1e-12,
with exact integer illumination and whole-second events. These measurements are
coverage evidence, not a proof across every coordinate or floating-point library.

Live results never enter the deterministic fixture iterator; cases live in
`contracts/fixtures/astronomy/cases.json` with no numeric goldens.

## Composition boundary

**Normative.** This result is an external provider fact, not a deterministic one.
Its cross-host agreement is tolerance-bounded, and those tolerated differences are
*not* absorbed by `targets.moon_recommendation`, whose thresholds are strict
cut-points. A host must not derive its own observation here and expect another
host's lunar score to match: the single canonical observation must be injected
into every consumer. The full evidence, the list of vulnerable cut-points and the
product rule are in contracts/procedures/moon-recommendation.md.

## Out of scope

Phase names, emoji and localized text; moonrise/moonset presentation; scoring,
windows and reasons (`targets.moon_recommendation`); planets; mixed-target
composition; historical dates.

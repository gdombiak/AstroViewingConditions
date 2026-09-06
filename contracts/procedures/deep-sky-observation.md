# Deep-sky observation facts (unreleased 1.0)

## Boundary review

Audit lead verdict: **Partially Agree**. Everything the audit listed exists in
`DeepSkyTargetPositionProvider` (apps/ios/.../DeepSkyCatalogService.swift), but
three of its statements are imprecise about the real runtime semantics:

- "15-minute sampling over an astronomical-night interval" is a *default*, not a
  constant: `minimumAltitude` (15) and `sampleInterval` (900 s) are constructor
  parameters, and production tests already construct the provider with 40 and -90.
- "best time selected from the highest sampled altitude" is true only *per visible
  run*, and the maximum is taken over the run, not over the whole night; on a tie
  the **earliest** sample wins (Swift `max(by:)` keeps the first maximal element).
- "interpolated threshold crossings" applies only to *interior* run edges. A run
  touching sample index 0 reports the interval start, and a run touching the last
  sample index reports the interval **end**, even when the last sample instant is
  strictly before that end (interval length not divisible by the sample interval).

The audit also omits: the `>= 0.0001` degenerate-slope guard, the `[0,1]` clamp on
the interpolation fraction, geometric (unrefracted) altitude, the doubled degree
normalization of local sidereal time, and the 8-point compass code derived from the
best sample's azimuth.

Chosen boundary: **two capabilities**, matching the two things production actually
does in sequence.

1. `astronomy.horizontal_position`, `since: "1.0.0"` — the closed-form numeric
   equatorial→horizontal conversion at one instant. Deterministic; it is *not* a
   live ephemeris provider despite the namespace, and it neither reads the catalog
   nor calls SunCalc/skyfield.
2. `targets.deep_sky_windows`, `since: "1.0.0"` — deep-sky visible-run/window
   semantics over an explicit interval, built on (1).

Public count becomes 23. Engine identity remains unreleased 1.0.0; no release.

Rejected alternatives:

- **One combined `deep_sky.observation` capability.** The numeric conversion is the
  only place the coordinate/sidereal/azimuth wrap rules live, and folding it into
  the window capability makes those rules testable only indirectly through window
  endpoints. Splitting lets wrap behavior use direct exact-per-instant fixtures.
- **A generic `targets.windows` abstraction shared by deep sky, Moon and planets.**
  Production has three genuinely different providers with different thresholds
  (deep sky 15°, planets 8°, Moon > 0°), different sources (fixed catalog, Schlyter
  low-precision elements, SunCalc), different endpoint rules and different
  eligibility. `PlanetRecommendationService` re-derives a structurally similar but
  separately written horizontal step with its own hour-angle and azimuth
  normalization order. A shared name today would freeze float-level details of one
  path onto the others before those slices are reviewed.
- **Reusing the Phase 16 live astronomy (`astronomy.moon_*`) math.** That path is
  SunCalc/skyfield-backed and *refracted*; the deep-sky path is geometric. Swapping
  it in would silently change production altitudes and therefore scores.
- **Exposing only a typed Swift/Python API with no capability ID.** The Bot needs
  these facts, and target recommendation composition upstream consumes them; a
  private API would leave the fact set unverified across hosts.

## `astronomy.horizontal_position`

`injected` has exactly:

- `right_ascension`: finite number, **hours**;
- `declination`: finite number, degrees;
- `latitude`: finite number, degrees;
- `longitude`: finite number, degrees, **east positive**;
- `time`: UTC instant in exact `YYYY-MM-DDTHH:MM:SSZ` form, inside the supported
  range below.

All five are required. Unknown keys, nulls, booleans, non-finite numbers, offsets,
fractional seconds and non-Gregorian dates are invalid. Latitude and longitude are
*not* range-checked or wrapped: production passes device coordinates straight
through and the formula is periodic. Errors use code `validation`, message
`invalid astronomy.horizontal_position input`.

Normative computation, in exactly this order and in binary64:

1. `julian_date = epoch_seconds / 86400 + 2440587.5`
2. `days_since_j2000 = julian_date - 2451545.0`
3. `gst_deg = norm360(280.46061837 + 360.98564736629 * days_since_j2000)`
4. `lst_deg = norm360(gst_deg + longitude)` — note `norm360` is applied twice,
   at step 3 and again here. Preserve both applications.
5. `hour_angle = radians(norm180(lst_deg - right_ascension * 15))`, where
   `norm180(x) = norm360(x) > 180 ? norm360(x) - 360 : norm360(x)`
6. `sine_alt = sin(dec)·sin(lat) + cos(dec)·cos(lat)·cos(H)`, then
   `altitude = degrees(asin(clamp(sine_alt, -1, 1)))`. The clamp is a domain
   guard: binary64 rounding can push the trigonometric identity slightly outside
   `[-1, 1]` at zenith/nadir. Unclamped, Python `math.asin` raises and Darwin
   `asin` returns NaN, so a sample at the zenith would fail `altitude >= threshold`.
7. `azimuth = norm360(degrees(atan2(sin(H), cos(H)·sin(lat) - tan(dec)·cos(lat)) + π))`
   — π is added in **radians before** the degree conversion.

`norm360(x)` is `fmod(x, 360)` with 360 added when the result is negative (so a
result of exactly `-0.0` stays `-0.0`; it compares equal to 0). Degrees/radians use
`x·π/180` and `x·180/π`.

### Supported instant range

Both capabilities accept only instants from `2000-01-01T00:00:00Z` through
`2499-12-31T23:59:59Z`, **inclusive**, on every timestamp field. Anything outside
that range is `validation`, not a clamped or normalized value.

This is a deliberate fixed modern product range, not a historical astronomy range.
Astro Conditions and the Astronomer Bot forecast and plan observing sessions; they
have no requirement to answer for past or far-future centuries. Restricting the
domain also closes a cross-host portability hole: before the 1582 Gregorian
cutover, Foundation's ISO-8601 parser falls back to the Julian calendar while
Python's `datetime` stays proleptic Gregorian, so the two hosts resolve the *same
string* to instants two or more days apart. The lower bound sits well clear of
that boundary, so the accepted domain is unambiguous on both hosts by
construction rather than by convention.

The bound instants are `946684800` and `16725225599` seconds from the Unix epoch;
both hosts parse those two strings to exactly those values.

The range is enforced on formatted output as well as input. Window endpoints
always lie inside the injected interval, so an in-range request can never produce
an out-of-range instant; the output check is a fail-closed backstop, not a second
policy. It is scoped to these two capabilities and changes no other capability's
timestamp contract.

Altitude is **geometric**: there is no atmospheric refraction, no parallax, no
proper motion, no precession/nutation of the catalog coordinates, and UT1 is taken
as UTC. Do not substitute a more accurate model; production scores depend on this
one. Output is exactly `{ "altitude": <deg>, "azimuth": <deg in [0,360)> }`.

## `targets.deep_sky_windows`

`injected` keys:

- exactly one of `target_id` (a canonical `contracts/data/catalog/deep-sky.json`
  entry id, matched byte-for-byte) **or** the pair `right_ascension` +
  `declination`. Supplying both, neither, or only one half of the pair is invalid.
  Canonical coordinates are authoritative; do not restate them in fixtures.
- required `latitude`, `longitude`: finite numbers, degrees, east-positive.
- required `night_start`, `night_end`: UTC `YYYY-MM-DDTHH:MM:SSZ`, each inside the
  supported range below. The range applies per field; an inverted interval is
  still allowed and simply yields no samples.
- optional `minimum_altitude`: finite number, degrees. Default `15`.
- optional `sample_interval_seconds`: finite number **strictly greater than 0**.
  Default `900`. Also subject to the sampling work cap below.

An unknown `target_id` is `validation`, not an empty result: the production guard
that returns `[]` for a non-deep-sky or unknown target is *composition* in
`DefaultTargetRecommendationService`, not a fact about a deep-sky target. Errors
use code `validation`, message `invalid targets.deep_sky_windows input`.

`sample_interval_seconds > 0` is validation added by the engine. Production reaches
this code only from a host-owned constructor and would not terminate at 0.

### Sampling work cap

A request must not require more than **10 080 samples**. This is a transport
resource bound, not a product rule: it invents no minimum cadence and no maximum
night length. Requests over the bound fail with
code `sample_cap` and message
`targets.deep_sky_windows exceeds the 1.0 sample cap (10080 samples)`.

The limit mirrors `location.grid`'s 885-point cap in shape and placement: derived
from a stated maximal geometry, enforced in the capability transport, and checked
by a preflight that does bounded work. 10 080 is seven days of one-minute cadence.
Production asks for one astronomical night at the 900-second default — at most
about 96 samples even for a maximal polar night — so the bound admits every
product geometry by more than two orders of magnitude while keeping worst-case
work at ~10⁴ evaluations.

Compute the bound without iterating. With `span = night_end - night_start`:

1. `span < 0` is **not** a cap: an inverted interval emits no samples and does no
   work, exactly as non-positive grid radius/spacing is not a grid cap.
2. Let `pivot` be whichever of `night_start`/`night_end` has the larger magnitude
   on the reference-epoch scale. If `pivot + sample_interval_seconds <= pivot`,
   the step cannot advance binary64 and the sampling loop would never terminate;
   treat that as exceeding the cap. Checking only the larger-magnitude endpoint is
   sufficient because the ULP is monotonic in magnitude, so a step that advances
   there advances everywhere in the interval.
3. Otherwise bound the **realized** step. Each `time = time + interval` is rounded
   to nearest, so the step the loop actually takes is `interval + δ` with
   `|δ| <= ulp(pivot) / 2`; the smallest step it can take is
   `effective = sample_interval_seconds - ulp(pivot) / 2`. If `effective <= 0`,
   forward progress is not guaranteed — treat that as exceeding the cap.
   Otherwise let `quotient = span / effective`. The loop runs at most
   `floor(quotient) + 1` iterations, so accept only when `quotient` is finite and
   `quotient < 10080`. Never materialize the count as a machine integer before
   this test: the quotient can exceed the integer range.

This is a **conservative** bound, not an exact iteration count. `effective`
assumes every step loses the full half-ULP, which real rounding rarely does, so
the test guarantees one direction only: every accepted request executes at most
10 080 samples. It may reject a near-cap request whose actual loop would have
emitted 10 080 or fewer — for example `span = 60` seconds with
`sample_interval_seconds = 0.005952419517518096` near the 2026 epoch runs exactly
10 080 iterations yet is rejected. That is the intended trade: the preflight stays
non-iterative and cheap, and the only way to characterize such inputs exactly
would be to run the loop the cap exists to avoid.

Do **not** bound with `span / sample_interval_seconds`. That quotient counts the
mathematical series `night_start + k · interval`, which the normative
repeated-addition loop does not follow. Because each addition can round down by up
to half a ULP, the loop can emit more samples than that quotient predicts. A
concrete case near the 2026 epoch: `span = 1` second with
`sample_interval_seconds = 9.921520770703732e-05` gives
`span / interval ≈ 10079.1`, which the mathematical formula would accept, while
repeated addition actually emits 10 083 samples. The `effective` denominator above
rejects it, and no accepted request can exceed 10 080 iterations.

Step 2 is required in addition to step 3. A zero-length interval has
`quotient == 0` and passes the count test, yet a non-advancing step still loops
forever; step 2 is what rejects it.

The cap lives in transport only. The typed Swift and Python sampling APIs are
unchanged and remain unbounded, matching `generate_grid`/`generateGrid`, which
likewise do not apply their capability's cap. Production constructors, the
900-second default, endpoint inclusion and repeated-addition semantics are
untouched. The bound does reject inputs that were previously transport-valid: any
request whose sampling loop is unbounded or would run more than 10 080 iterations
now fails with `sample_cap` instead of hanging or grinding. Every request still accepted returns an identical
result. Product-relevant geometry is unaffected: production cadences sit three
orders of magnitude inside the bound, so nothing the app or Bot asks for
approaches the region where the conservative margin can bite. What the cap
newly rejects is unbounded requests, over-cap requests, and a narrow band of
pathological near-cap inputs whose safety cannot be established without
iterating.

### Sampling

Let `t0 = night_start`. Emit sample `k` at `t0 + k · sample_interval_seconds` for
`k = 0, 1, 2, …` **while `t_k <= night_end`**, accumulating the instant by repeated
addition of the interval (not by multiplication). Both endpoints are inclusive:
`night_end` is sampled only when it falls exactly on a step.

- `night_end < night_start` (inverted) yields zero samples and `{"windows": []}`.
- `night_end == night_start` yields exactly one sample.
- An interval that is not a whole multiple of the step simply stops early; the
  remainder is never sampled.

Each sample carries `astronomy.horizontal_position` altitude and azimuth.

### Visible runs

A sample is visible iff `altitude >= minimum_altitude` (**inclusive**; equality is
visible). Scan samples in order and emit one window per maximal contiguous run of
visible samples. A run of length 1 is a window.

For a run covering sample indices `[i, j]`:

- `max_altitude` and `azimuth` come from the run's **highest-altitude** sample;
  on a tie the **earliest** such sample wins. `best_time` is that sample's instant.
- `direction` is the 8-point code of that azimuth (below).
- `start` is `night_start` when `i == 0`, else the crossing between samples
  `i-1` and `i`.
- `end` is `night_end` when `j` is the **last sample index**, else the crossing
  between samples `j` and `j+1`.

The `end` rule is a preserved quirk: when the interval is not a whole multiple of
the step, a run that reaches the last sample reports `night_end`, which is later
than the last instant actually evaluated.

### Threshold crossing

For an ordered sample pair `(a, b)`:

```
delta = b.altitude - a.altitude
if abs(delta) <= 0.0001: return a.time
fraction = clamp((minimum_altitude - a.altitude) / delta, 0, 1)
return a.time + (b.time - a.time) * fraction
```

The guard is `<= 0.0001` degrees on the **absolute** altitude change, and the
clamp is applied after the division. Both are load-bearing: they keep a flat or
overshooting pair from producing an instant outside `[a.time, b.time]`.

Sampling and interpolation are performed as binary64 seconds relative to
2001-01-01T00:00:00Z (the production Swift `Date` reference epoch), so both hosts
execute the same IEEE operations and the Swift result is bit-identical to the
pre-migration production code.

### Compass direction

`directions = [N, NE, E, SE, S, SW, W, NW]`, and the code is
`directions[trunc((norm360(azimuth) + 22.5) / 45) mod 8]`, where `trunc` truncates
toward zero (Swift `Int(Double)` / Python `int(float)`). Because the azimuth is
already in `[0, 360)` the quotient lies in `[0.5, 8.5)`, so index 8 wraps to `N`.
These are objective codes, not presentation copy; host summaries render them.

### Output

```
{ "windows": [ { "start", "end", "best_time", "max_altitude", "azimuth", "direction" } ] }
```

Windows are in ascending sample order. `start`, `end` and `best_time` are UTC
`YYYY-MM-DDTHH:MM:SSZ` obtained by flooring the epoch second toward negative
infinity; a value outside the supported range is a validation failure. Flooring loses
sub-second precision on interpolated crossings **in transport only** — the typed
Swift and Python APIs return full binary64 instants, and the iOS production caller
uses the typed API, so its scoring inputs are unchanged.

This is the whole objective fact set consumed upstream of recommendation:
`TargetVisibilityWindow.start/end/bestTime/maxAltitude/azimuth/direction`. Nothing
else is added; `TargetVisibilityWindow.id` is a host-derived identity and `duration`
is derived.

## Equality and tolerances

`astronomy_horizontal_position` and `deep_sky_windows` compare `altitude`/
`max_altitude`/`azimuth` with `abs_1e9` degrees (≈3.6e-6 arcsec). The formula is a
fixed sequence of binary64 operations; the only cross-host freedom is libm ULP
noise in `sin/cos/tan/asin/atan2`, which is many orders below this bound. It is not
copied from the Phase 16 live-astronomy `abs_0_5`: that tolerance exists because
SunCalc and skyfield are different *models*, whereas these two hosts implement one
formula. Timestamps and `direction` are **exact**.

Highest-altitude ties and the degenerate-slope guard are covered by typed Swift and
Python unit tests rather than fixtures: an exact binary64 tie between two trig
samples cannot be constructed reliably, and a near-tie would make the fixture
depend on libm ULPs.

## Adjacent responsibilities that stay out of this slice

- `DefaultMoonTargetRecommendationProvider` and
  `DefaultPlanetTargetRecommendationProvider` keep their own thresholds, sources,
  eligibility and window rules. Not ported.
- Mixed-target composition in `DefaultTargetRecommendationService` (specialized
  provider first, deep-sky provider as the fall-through, `TargetScoring.rankedIndices`)
  stays host-side.
- `targets.recommend` remains deterministic over injected/precomputed windows and
  weather/Moon facts. It does not call these capabilities; nothing here reaches
  scoring by itself.
- Equipment matching, Best Nearby, multi-night composition, Bot orchestration and
  live weather acquisition are unchanged.

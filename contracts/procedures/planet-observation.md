# Planet observation facts (unreleased 1.0)

Capability: `astronomy.planet_observation`, `since: "1.0.0"`, `hosts: [ios, cli]`,
equality `astronomy_planet_observation`. **Live/provider-derived**: planet
positions are calculated for the requested night. Both hosts run the production
low-precision orbital-element model; no external ephemeris file or network is
required. The deterministic consumer is `targets.planet_recommendation`
(contracts/procedures/planet-recommendation.md).

## Boundary review

Audit verdict: **Agree, with corrections.** The 900 s cadence, the two-hour lead
before astronomical-night start, the one-hour trail after its end, the Schlyter
`JD - 2451543.5` day number and Earth's role in the geocentric vector all exist
in production, in `LowPrecisionPlanetAstronomyProvider`
(apps/ios/Sources/SharedCode/Core/Services/PlanetRecommendationService.swift).
Five statements needed correction before extraction:

- **The astronomy provider accepts `earth`.** Production maps a target id through
  `PlanetOrbitalElements.Planet(rawValue:)`, whose cases are earth, venus, mars,
  jupiter and saturn. No production catalog row is `earth`, and the recommendation
  provider additionally requires `target.type == .planet`, so this is unreachable
  in the app. The shared `PlanetBody` keeps `earth` so the host mapping is
  unchanged; the **capability rejects it**, along with every other id outside
  `catalog.solar_system`'s planet rows.
- **The sampling loop has no explicit interval-end sample.** Unlike
  `astronomy.moon_observation`, the loop is `while time <= end` with repeated
  addition and nothing after it. A span that is not a whole multiple of the
  cadence simply stops at the last step inside it.
- **An inverted night interval is not automatically empty.** The guard is
  `end > start` on the *sampled* span, i.e. `nightEnd + 3600 > nightStart - 7200`.
  A night inverted by less than three hours still yields samples; only a longer
  inversion yields no observation at all, which is `nil` in production and
  `observation: null` here.
- **`solarElongation` is never `nil` from this provider.** The production DTO
  declares it optional, but the low-precision provider always computes it. The
  transport therefore always emits a number; the *recommendation* transport
  accepts `null` because injected facts may omit it.
- **Altitude and azimuth are not the deep-sky conversion.** The planet path does
  not clamp the spherical identity before `asin`, and it normalizes azimuth as
  `normalizedDegrees(degrees(atan2(...)) + 180)` rather than adding π in radians.
  Those two expressions are not bit-identical, so the planet path keeps its own.

Rejected alternatives:

- **Skyfield or any higher-precision ephemeris.** Production ships the Schlyter
  low-precision model. Replacing it would move every altitude, every visible-run
  boundary and therefore every planet score. Accuracy is not the goal here;
  reproducing production is.
- **Reusing `astronomy.horizontal_position`.** That capability is the deep-sky
  closed-form conversion for fixed RA/Dec. It clamps and it builds azimuth
  differently. Sharing it would silently change planet numbers.
- **Emitting only the night interval and letting the caller widen it.** The lead
  and trail are part of the production observation, and the Venus twilight terms
  depend on samples outside astronomical night.

## Inputs

Object with exactly `target_id`, `latitude`, `longitude`, `night_start`,
`night_end`, and an optional `sample_interval_seconds`.

- `target_id`: one of `venus`, `mars`, `jupiter`, `saturn` — the production
  `catalog.solar_system` planet rows, lowercase and exact. `earth`, `moon`,
  `mercury` and any other identity are rejected.
- `latitude` / `longitude`: finite JSON numbers in `[-90, 90]` / `[-180, 180]`.
  JSON booleans are not numbers and are rejected.
- `night_start` / `night_end`: whole-second `YYYY-MM-DDTHH:MM:SSZ` instants that
  round-trip exactly, from `2000-01-01T00:00:00Z` through `2049-12-31T23:59:59Z`
  inclusive — the same window as the rest of the `astronomy.*` namespace.
  `night_end - night_start` must be at most 26 hours. It may be negative.
- `sample_interval_seconds`: finite integral seconds in `1...93600`; default `900`.
  Whole seconds prevent duplicate floored timestamps and host-dependent cadence
  accumulation.

Resource bounds, all checked before any sampling runs:

- the 26-hour span bound above;
- a 1440-sample cap over the *sampled* span `[night_start - 7200, night_end + 3600]`,
  using the same conservative preflight as `targets.deep_sky_windows`, which also
  rejects a cadence too small to advance binary64;
- integral cadence.

A cap failure reports `code: "sample_cap"`; every other rejection reports
`code: "validation"` with the message `invalid astronomy.planet_observation input`.

## Procedure

1. `sample_start = night_start - 7200`, `sample_end = night_end + 3600`.
2. If `sample_end <= sample_start`, there is no observation: emit `observation: null`.
3. Otherwise sample by repeated addition from `sample_start` while
   `time <= sample_end`. There is no explicit endpoint sample.
4. At each instant, with `jd = seconds_since_1970 / 86400 + 2440587.5` and
   `d = jd - 2451543.5`:
   - take Earth's Schlyter elements at `d` and convert them to heliocentric
     rectangular coordinates — in this convention that vector *is* the geocentric
     Sun vector;
   - do the same for the requested planet and add the two vectors to get the
     geocentric planet vector;
   - rotate by the obliquity `23.4393 - 3.563e-7 * d` to equatorial coordinates
     and take `atan2` for right ascension and declination;
   - local sidereal time is `280.46061837 + 360.98564736629 * (jd - 2451545.0) + longitude`,
     normalized to `[0, 360)` and converted to radians;
   - altitude is `asin(sin δ sin φ + cos δ cos φ cos H)` with **no clamp**, and
     azimuth is `normalizedDegrees(degrees(atan2(sin H, cos H sin φ - tan δ cos φ)) + 180)`;
   - solar elongation is the angle between the geocentric planet vector and the
     geocentric Sun vector, with the cosine clamped to `[-1, 1]`, and `0` when
     either magnitude is non-positive.

The eccentric anomaly uses production's single correction term,
`E = M + e sin M (1 + e cos M)`, not an iterated Kepler solve. Operation order in
both hosts follows the Swift source so binary64 results agree.

## Output

```
target_id, night_start, night_end,
observation: null | { sample_start, sample_end, samples: [{ time, altitude, azimuth, solar_elongation }] }
```

`night_start` / `night_end` echo the request. `sample_start` and `sample_end` are
the lead/trail endpoints, not the last sampled instant. Sample instants are whole
seconds by construction and are strictly increasing. Altitude is degrees,
geometric, with no refraction or parallax; azimuth is degrees from north in
`[0, 360)`; solar elongation is degrees in `[0, 180]` and is never null from this
capability.

The sampling lead and trail can reach up to two hours before and one hour after
the accepted instant window, so `sample_start` may be in 1999 and `sample_end`
in 2050. The transport reports those instants rather than clamping them, and
`targets.planet_recommendation` accepts them: its injected-sample range carries
exactly this `-7200 / +3600` bounded spill around its own night range. See that
procedure's "Bounded spill on provider-derived instants".

## Equality

Policy `astronomy_planet_observation`. `target_id`, both echoed instants,
`sample_start`, `sample_end`, sample `time` and null-observation presence are
exact. Altitude and solar elongation use `abs_1e4`; azimuth uses the cyclic
`cyclic_azimuth_abs_0_01`, because a plain absolute difference would report ~360
for two values that are neighbours across north.

Measured Swift/Python agreement over the adversarial sweep in
`Tests/parity/test_planet_model.py` is **bit-exact** — 0.0 worst difference on
altitude, azimuth and solar elongation across the four planets, six dates
spanning 2000–2049, thirteen locations including both poles and the antimeridian,
inverted and zero-length intervals, non-divisible spans and an azimuth-wrap
transit sweep. The public ceilings above leave room only for libm ULP differences
between platforms; the adversarial test asserts a far tighter `1e-9`, so a
regression to a different astronomy model fails even where it would fit the
public policy.

## Composition boundary

This capability is a **provider fact**. A result is consumable **verbatim** by
`targets.planet_recommendation`, spill-region samples included.
`targets.planet_recommendation` is deterministic and exact *given* injected
facts. Running the live capability on
each host and feeding each host its own result is exact only while both hosts run
this same model, which they do today. It is not a contract guarantee: every
recommendation decision is a strict cut-point on a live quantity, so a host that
derived positions from a different model could land on the other side of one, and
no tolerance value prevents that. Freeze one observation and inject it wherever
one answer is required.

## Out of scope

Scoring, visibility windows, reason codes, English copy, Mercury/Uranus/Neptune,
mixed-target composition, equipment awareness, Best Nearby, multi-night forecast
eligibility, and any change to `astronomy.moon_observation` or
`targets.deep_sky_windows`.

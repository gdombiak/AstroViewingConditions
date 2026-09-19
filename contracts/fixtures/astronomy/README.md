# Phase 16 live astronomy cases

`cases.json` is manually authored input/semantic data, applicable to
`>=1.0.0 <2.0.0`. It contains no numeric output goldens. Both implementations
must independently satisfy the semantic checks; the parity runner then uses
field-level tolerances symmetrically. Live results never enter the deterministic
capability fixture iterator.

| Cases | Purpose |
|---|---|
| California equinox, winter, summer | Ordinary night ordering and seasonal variation; events on the following UTC date. |
| New York spring/fall DST | Caller-resolved 23/25-hour local-noon intervals, with no engine timezone guess. |
| Auckland | Southern hemisphere, positive UTC offset, evening and morning across local/UTC dates. |
| Tromso summer | Polar day: every crossing missing. Prevent a 365-day search from returning distant events. |
| Tromso winter | No visible sunrise/sunset, but twilight still exists; per-field missing identity. |
| London summer | Sunrise/sunset exist without astronomical night. |
| North Pole winter | Continuous darkness without crossings, still explicit null (no synthetic night boundaries). |
| Short daylight interval | No event in the requested minute even though the same date has sunrise/sunset. |
| Full Moon above/below horizon | High geometric illumination at opposite parts of the day; negative altitude preserved. |
| New Moon | Low illuminated fraction independently justified by the April 8, 2024 solar eclipse. |
| Quarter Moon | Broad 45–55% illumination semantics; the current library pair exercises the allowed one-point difference symmetrically, without per-engine goldens. |
| Hourly observing window | 17 UTC samples through one window, changing altitude and crossing the horizon. |
| Repeated DST hours | Two local 01:00 hours retained as distinct UTC instants. |
| Empty series | Exact empty structure without sampling or resource access. |
| Moon observation: full above | Full Moon up for the whole interval: `always_up`, no events, every sample above the horizon. |
| Moon observation: rises / sets | One crossing inside the interval, clearing the opposite always-flag. |
| Moon observation: always down | A whole interval below the rise/set threshold, with `always_down` and no events. |
| Moon observation: new Moon | The April 8, 2024 new Moon: illumination at most 1 and a phase within 0.04 of the 0/1 wrap. |
| Moon observation: southern hemisphere | Positive UTC offset and a southern-sky Moon that sets during the interval. |
| Moon observation: shorter than cadence, zero-length, inverted | Two, one and zero samples: the explicit interval-end sample and the guarded inverted interval. |
| Moon observation: hourly cadence | A caller cadence other than the production 1800 s. |
| Moon observation: end not divisible | Interval length not a whole number of cadences, so the last step is short. |

The March 25, 2024 full-Moon and April 8 new-Moon contexts are independently
supported by [NASA's 2024 eclipse list](https://eclipse.gsfc.nasa.gov/OH/OH2024.html).
Illumination here is geometric phase fraction, not an eclipse-shadow brightness
model. The numeric tests assert only broad high/low ranges, not times or
positions copied from either implementation.

Moon observation cases assert structure, cadence, event/flag consistency and the
per-case semantic only; the parity runner then compares the two engines
symmetrically under `astronomy_moon_observation`, whose azimuth and phase
tolerances are cyclic. Sample counts are asserted per case, so a cadence or
interval-end regression fails even when the numbers stay inside tolerance.

Additional unit/transport regressions cover invalid Gregorian dates, leap-day
validity, timezone-offset and leap-second rejection, coordinate booleans and
nonfinite values, unknown keys, duplicate/reversed/oversized series, maximum
intervals, half-open bounds using an injected boundary sampler, truncation,
process-timezone independence, malformed/missing ephemerides, network blockers,
and scoring isolation. Comparator tests exercise both directions at and beyond
60 seconds, 0.5 degrees and one integer percentage point, as well as null,
missing/extra keys and sample identity failures.

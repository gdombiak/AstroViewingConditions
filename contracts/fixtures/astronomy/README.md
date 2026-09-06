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

The March 25, 2024 full-Moon and April 8 new-Moon contexts are independently
supported by [NASA's 2024 eclipse list](https://eclipse.gsfc.nasa.gov/OH/OH2024.html).
Illumination here is geometric phase fraction, not an eclipse-shadow brightness
model. The numeric tests assert only broad high/low ranges, not times or
positions copied from either implementation.

Additional unit/transport regressions cover invalid Gregorian dates, leap-day
validity, timezone-offset and leap-second rejection, coordinate booleans and
nonfinite values, unknown keys, duplicate/reversed/oversized series, maximum
intervals, half-open bounds using an injected boundary sampler, truncation,
process-timezone independence, malformed/missing ephemerides, network blockers,
and scoring isolation. Comparator tests exercise both directions at and beyond
60 seconds, 0.5 degrees and one integer percentage point, as well as null,
missing/extra keys and sample identity failures.

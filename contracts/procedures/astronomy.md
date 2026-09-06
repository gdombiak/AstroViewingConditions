# Live sun and Moon astronomy (unreleased 1.0.0)

This is a language-neutral product contract, independent of either library's
ephemeris approximation. Swift uses the existing SunCalc 1.0.0 resolution;
Python uses Skyfield. Neither implementation supplies golden numeric values.
These capabilities never call weather providers or deterministic scoring.

## Inputs and time

All three use the existing `{capability, injected}` envelope. `injected` has
`latitude` in [-90,90] and east-positive `longitude` in [-180,180], finite JSON
numbers (not booleans). No other location facts are required: the production
samplers use sea level, a spherical latitude, and an unobstructed horizon.
Elevation, saved locations, device location and timezone discovery are absent.
Unknown input keys fail validation.

Times are strict Gregorian `YYYY-MM-DDTHH:MM:SSZ`, whole UTC seconds, in
[2000-01-01T00:00:00Z, 2050-01-01T00:00:00Z). Leap-second labels, offsets,
fractional seconds and normalized invalid calendar dates fail validation.
This deliberately bounded modern-date contract is inside DE421 coverage.
UTC arithmetic uses POSIX seconds; no local calendar projection or device-clock
default determines requested instants.
Hosts resolve a civil date and IANA timezone to explicit instants first. A
local noon-to-next-noon observing request can be 23 or 25 hours across DST;
it must not be constructed by adding a fixed 24 hours to local noon.

## astronomy.sun_events

Additional inputs: `start`, `end`, with 0 < end-start <= 26 hours. Search the
half-open interval [start,end). Return the first upward and first downward
crossing of each threshold within that interval. Morning means upward and
evening means downward; it does not mean a particular UTC date. A host should
choose local noon to next local noon for one observing night. A midnight-based
query is also valid, but its morning can precede its evening.

Result always contains `start`, `end`, `sunrise`, `sunset`,
`civil_twilight_begin`, `civil_twilight_end`, `nautical_twilight_begin`,
`nautical_twilight_end`, `astronomical_twilight_begin`,
`astronomical_twilight_end`, `astronomical_night_start`,
`astronomical_night_end`. All event fields are UTC strings or explicit null.
Begin is the upward crossing; end is the downward crossing.

| Fields | Definition |
|---|---|
| sunrise / sunset | Visible upper solar limb at the sea-level horizon. Geocentric center altitude threshold is -R + asin(6371/d) - asin(695700/d), in radians; d is geocentric Sun distance in km and R = pi / (10800 tan(radians(7.31/4.4))). This is approximately -0.83 degrees, varies with distance, and is not Skyfield's fixed -0.8333-degree default. |
| civil begin / end | Geocentric solar center at -6 degrees; no refraction or parallax correction. |
| nautical begin / end | Geocentric solar center at -12 degrees; no refraction or parallax correction. |
| astronomical begin / end | Geocentric solar center at -18 degrees; no refraction or parallax correction. |
| astronomical night start / end | Aliases of astronomical twilight end / begin, respectively. They describe a complete night only when both exist and start < end; no duration or synthetic boundary is inferred. |

No crossing means null, including polar day/night and a truncated interval.
Null alone does not distinguish continuous darkness from continuous daylight.
Tangency without a crossing is not an event. Selection uses unrounded times;
serialization truncates to whole UTC seconds so an event before end cannot
round outside the interval. Each event field compares symmetrically with
absolute difference <= 60 seconds; null must match null. `start` and `end`
are exact. Structural keys and aliases are exact invariants.

The <=60-second and exact-null-identity parity guarantee applies to ordinary
diurnal crossings. Seasonal threshold crossings at exactly latitude +90 or -90
degrees have zero diurnal motion; this degenerate geometry can amplify library
differences beyond 60 seconds or produce an event in one library and null in the
other within a bounded interval. This exception is limited to seasonal crossings
at the exact geographic poles: latitude [-90,90] remains accepted, and the
existing tolerance and null-identity requirements remain unchanged elsewhere,
including ordinary high-latitude cases such as Tromso.

## astronomy.moon_info

Additional input: `time`, one explicit instant. Result: `time` (exact),
`altitude` (degrees, absolute difference <= 0.5), `illumination` (integer
percent, absolute difference <= 1). Illumination is geocentric illuminated
disc fraction, normalized by truncating 100*fraction toward zero, as in the
production `MoonIlluminationSample`. No rounding to nearest; this is geometric
phase fraction, not an eclipse-shadow or observed-brightness model.

Altitude preserves the actual product quantity: rotate the **geocentric**
Moon direction into the observer's spherical horizontal frame, with no lunar
parallax subtraction. For true altitude h in radians, add zero below 0,
otherwise add 0.000296706 / tan(h + 0.00312537/(h + 0.0890118)). This is the
production standard-atmosphere refraction convention; a default topocentric
Skyfield altaz is a different quantity and is not interchangeable. This
approximate product altitude must not be advertised as precision topocentric
astrometry. Neither implementation is adjusted to match another's output.

Existing phase is a continuous signed illumination angle, with different
presentation bins in host AstronomyService and MoonObservation. No new phase
taxonomy, waxing/waning threshold, name or emoji is contracted in this phase.
Rise/set belong to the separate recommendation observation path and are absent.

## astronomy.moon_series

Additional input: `times`, an ordered, strictly increasing array of 0...49
explicit UTC instants, spanning at most 48 hours. Result: `samples`, one
moon_info row per input, in that order. Timestamp identity and array length
are exact; altitude and illumination use the moon_info field tolerances.
The host normally supplies hourly forecast instants through its half-open
observing window. The engine neither generates local hours nor interpolates,
inserts an end sample, silently deduplicates, or filters caller instants.
Both repeated DST civil hours can appear because their UTC instants differ.

## Implementation and operational boundaries

SunCalc's existing unbounded sun sampler searches up to 365 days; the portable
path explicitly sets the interval limit. The old Apple API retains its search
behavior and Foundation missing-event approximation (`hosts: [ios]`, equality
n/a). Its nonoptional SunEvents cannot represent this portable result directly.
NightForecastFilter's host calendar projection remains unchanged. Portable
SunCalc calls select UTC explicitly; existing Apple calls retain their current
zone. SunCalc internally uses its low-precision distance approximation and a
Foundation day-of-year calculation (validated here with a Gregorian system
calendar); it is not an independent precision ephemeris.

Python installs pinned Skyfield and skyfield-data, opening DE421 locally with
`load_file`, and uses Skyfield's bundled timescale (`builtin=True`). A host may
inject a local ephemeris path; JSON cannot select a file. Missing or unreadable
data is an engine failure, never a download or astronomical null. See the
Python README for sizes, attribution, checksums and offline installation.

Live fixtures carry semantic expectations and input cases, not output dumps.
Cross-language tests apply equality-policy.yaml in both directions. Frozen
scoring fixtures and their exact integer expectations are unchanged. In
particular night_conditions.analyze still requires injected night_window and
moon_series; night_conditions.score and targets.recommend remain pure.

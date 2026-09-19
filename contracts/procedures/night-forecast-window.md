# Night forecast window (`night_forecast.derive_window`)

Normative procedure for the calendar/DST projection formerly owned only by
Swift `NightForecastFilter.calculateNightRange`.

## Boundary and ownership

Source archaeology found one portable Astro-domain fact: the pair of instants
used as the nighttime hourly-forecast window. `NightForecastFilter` does not add
another astronomical rule when it filters; it applies the ordinary half-open
predicate `forecast.time >= start && forecast.time < end`. The public capability
therefore derives only the window. Swift retains `filterToNighttime` as a typed
convenience over that authority. Forecast acquisition, the choice of observing
day and Sun-event rows, timezone acquisition, sorting, scoring and aggregation
remain caller/host composition.

This capability does not calculate Sun events. The host supplies the current
day's evening and morning astronomical-twilight instants and, when present, the
following day's morning astronomical-twilight instant. `astronomy.sun_events`
may be one source of those facts, but no provider capability is invoked here.

## Transport

The standard strict `capability`/`injected` envelope is used. `injected` has
exactly these keys:

| Field | Meaning |
| --- | --- |
| `observing_time` | Any instant whose local civil day is the observing day. Production normally supplies that day's start. |
| `time_zone` | Authoritative host-supplied location timezone identifier. |
| `astronomical_twilight_end` | Current Sun row's evening event; its local hour/minute supplies the start clock. |
| `astronomical_twilight_begin` | Current Sun row's morning event, used only as the missing-tomorrow fallback clock. |
| `tomorrow_astronomical_twilight_begin` | Following Sun row's morning event, or explicit JSON `null`. |

Instants are whole-second `YYYY-MM-DDTHH:MM:SSZ` in the shared engine range,
2000-01-01T00:00:00Z through 2499-12-31T23:59:59Z inclusive. Every derived
output must remain in that same range. Unknown or missing keys, offsets,
fractions, leap seconds, booleans/nulls in non-nullable fields, out-of-range
inputs and out-of-range derived outputs are `validation` with the exact message
`invalid night_forecast.derive_window input`.

The accepted timezone set is the same catalogued shared location-style set used
by `observing_night.resolve_active`:
`contracts/data/timezones/observing-night-zones.json`. Neither runtime's parser
defines the public surface. Fixed offsets, bare `UTC`/`GMT`, `Etc/*` and
non-location legacy names are rejected by both transports. The typed Swift API
takes an injected `Calendar`, and the typed Python API takes `ZoneInfo`; neither
typed API consults the transport catalogue. Timezone acquisition is host-owned.

Output is exactly:

```json
{"time_zone":"America/Los_Angeles","start":"2026-02-20T03:16:00Z","end":"2026-02-20T13:33:00Z"}
```

All three fields compare exactly. No tolerance applies.

## Normative projection

Using a Gregorian calendar pinned to `time_zone`:

1. `day = startOfDay(observing_time)`.
2. `following_day = add one calendar day to day`. Swift retains its unreachable
   24-hour fallback if Foundation returns `nil`.
3. Read only local `hour` and `minute` from `astronomical_twilight_end`.
   Discard its date and seconds. Set that hour/minute with second zero on `day`;
   if Foundation returns `nil`, fall back to the original twilight-end instant.
4. Choose the dawn source: tomorrow's begin when non-null, otherwise today's
   begin. Read only its local `hour` and `minute`; discard its date and seconds.
   Set that clock with second zero on `following_day`; if Foundation returns
   `nil`, fall back to the chosen source instant.
5. Return those two instants without ordering or duration validation.

No chronology is imposed because production imposes none. Degenerate or
inverted windows are valid typed results when the inputs produce them.

## Foundation calendar behavior frozen for Python

The start-of-day and day-addition operations reuse the operation-specific
Foundation emulation established for `observing_night.resolve_active`. Wall-time
replacement adds a third, distinct operation-specific policy. It is
Foundation's forward calendar-field search, not direct resolution of one local
datetime. `date(bySettingHour:minute:second:of:)` searches from **half a second
before** the containing day's first instant with matching policy `nextTime`,
repeated-time policy `first`, and direction `forward`, and re-runs the search
from that first instant if the first pass landed earlier. It matches hour, then
minute, then second over wall-clock-aligned calendar unit intervals whose length
stays a nominal 3600/60 seconds even where the next wall-clock boundary is
nearer or further. A candidate before the search start is rejected; when the
matched hour repeats, the search resumes one hour later rather than a whole day
later. Therefore:

- an ordinary clock resolves to its current-day exact instant;
- an ambiguous repeated clock selects the **first** (earlier) occurrence;
- a skipped midnight hour maps to that day's first instant;
- a conventional one-label spring jump such as Los Angeles 01:59 -> 03:00 is
  recognized as an inexact missing-hour match, so every projected 02:mm maps to
  the 03:00 transition boundary;
- other gaps do **not** obey a universal "first valid instant" rule. The
  hierarchical search may find the exact clock on a later civil day (Lord Howe
  02:15, Bahia Banderas 02:30, Godthab 23:30), or may adjust an inexact field
  match to an enclosing hour boundary (Chatham 02:45 -> 04:00);
- because the search begins before the day rather than at it, a request for the
  clock hour that ends the **previous** civil date can resolve onto that
  previous date. St. John's, Goose Bay and Moncton fall back at 00:01, so a
  2000-10-29 anchor returns 2000-10-28 23:01 for 23:01; Casey's three-hour
  backward jump at 23:00 makes a 2010-03-05 anchor return 2010-03-04 23:mm.

The nominal interval length explains the superficially valid Caracas cases. On
its 2016 half-hour base-offset jump the hour interval beginning at 02:00 still
runs 3600 seconds and so ends at 03:30, which is where the hour search first
sees the label 03. A request for 03:15 therefore advances to the following day's
exact 03:15 even though 03:15 exists on the transition day, while 03:30 remains
on it. Pyongyang's half-hour jump at midnight is the mirror case: 2018-05-04
23:30 does not exist, and the rejected candidate resumes the search at the next
day's first instant to return 2018-05-05 23:30 rather than overshooting a
further day. Python reproduces this exact operation shape explicitly; it does
not claim to be a general Calendar API.

A line-crossing dropped civil date is not excluded here. Unlike observing-night
day differencing over a bounded multi-day window, this algorithm performs only
one day-add, and the established emulation reproduces Foundation's 24-hour
fallback when that requested civil date does not exist. The Apia 2011-12-30
fixture pins that justified difference in acceptance policy.

## Production compatibility

`NightForecastWindowDeriver` is the typed Swift authority.
`NightForecastFilter.calculateNightRange` remains source-compatible and delegates
to it; `filterToNighttime` remains `[start,end)`. The production
`NightQualityAnalyzer` calls the deriver directly. An independent test-only copy
of the pre-migration Foundation operations is the migration oracle and compares
ordinary, conventional spring-forward, fall-back, midnight-transition, Lord
Howe, Chatham, Bahia Banderas, Godthab, Caracas, Casey, St. John's, Pyongyang,
non-hour-offset, missing-tomorrow and dropped-date cases without routing either
side through the same implementation. Manual parity fixtures freeze the public transport/calendar classes, while focused Swift/Python regression tests additionally pin the previous-civil-date search cases.
The Python emulation was additionally proved against Foundation by an exhaustive
differential scan over the whole accepted domain: all 442 catalogued zones for
2000-01-01 through 2499-12-31. Foundation reported 141,240 transitions there, of
which 141,180 change the UTC offset — 70,597 forward and 70,583 backward — and
match an independent Python discovery tuple for tuple; the remaining 60 change
only the DST flag and leave the offset unchanged, so they are invisible to every
operation this capability performs. Probing five instants around each transition
plus fixed ordinary dates gave 708,852 `startOfDay` comparisons, 708,852
one-calendar-day-add comparisons and 204,149,376 `date(bySettingHour:)`
comparisons across both anchor shapes, with a further 4,075,200 comparisons
sweeping all 1,440 clock values on each of the 2,830 structurally distinct day
shapes. All 205,567,080 comparisons agree, and Foundation never returned `nil`,
so its documented `nil` fallbacks are unreachable in this domain.

Cloud-timing classification, English summaries, provider fetching, geocoding,
timezone approximation, three-night composition and host orchestration are not
part of this capability.

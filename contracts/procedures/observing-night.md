# Active observing night (`observing_night.resolve_active`)

Normative procedure for the portable "which local observing night is Tonight?"
decision. It is the contract oracle for
`ObservingNightSelector` (Swift) and `astro_engine.observing_night` (Python).

## Source archaeology

Production's single cross-midnight authority is
`ActiveObservingNightResolver.resolve(conditions:referenceDate:timeZone:)`
in `apps/ios/Sources/SharedCode`. It delegates day selection to
`TargetRecommendationContextBuilder.resolve(conditions:dayOffset:referenceDate:timeZone:)`,
which mixes two unrelated jobs: the date/night identity decision migrated here,
and the assembly of `TargetRecommendationContext` (Moon info, hourly forecast
slice, `NightQualityAnalyzer` output). Only the first is portable. The builder
keeps the second, and after migration it is still the type that produces the
host recommendation context.

The astronomical-night boundaries themselves come from `AstroEngine.SunEvents`,
which already lives in the engine: `astronomicalNightStart` is
`astronomicalTwilightEnd` and `astronomicalNightEnd(using:)` prefers the
following day's `astronomicalTwilightBegin`. Those accessors are unchanged; this
capability restates the same composition over the two transported fields so a
non-Swift host reaches the same boundaries.

## Inputs

| Field | Meaning |
| --- | --- |
| `reference_time` | The instant being asked about. |
| `time_zone` | A catalogued shared location-style timezone identifier (see below). Already resolved by the host. |
| `forecast_start_time` | The first hourly-forecast timestamp, or `null` when the payload carries no hourly forecasts. |
| `daily_sun_events` | One row per represented day, aligned with the forecast's first day. Each row is `{astronomical_twilight_end, astronomical_twilight_begin}`. |
| `daily_moon_count` | How many daily Moon rows the same payload carries. |

`astronomical_twilight_begin` is that civil day's **morning** and
`astronomical_twilight_end` its **evening**, so a row is expected to read
"backwards" and **no chronological ordering is imposed on it**. A night window
deliberately spans two rows. Degenerate high-latitude days, where the production
`SunEvents` type still carries non-optional instants, are data rather than
malformed input.

Daily Moon data is transported as a count because the decision only
bounds-checks the array; no Moon fact participates.

Instants are whole-second `YYYY-MM-DDTHH:MM:SSZ` inside the shared engine range,
epoch `946684800` through `16725225599` — **2000-01-01T00:00:00Z through
2499-12-31T23:59:59Z inclusive**. `2500-01-01T00:00:00Z` is the first rejected
instant. (The target capabilities share those two epoch bounds; the extra spill
they document belongs to their own windows, not to this one.)

`daily_sun_events` is capped at 16 rows, the production
`BestSpotSearcher.maxForecastDays` maximum; exceeding that **transported array**
is `sample_cap`. `daily_moon_count` is a scalar, not a transported array, so a
value outside `0...16` is an out-of-domain scalar and is `validation`, like every
other malformed input: unknown top-level keys, unknown day-row keys, a missing
key, a JSON boolean where a number is required, an out-of-range instant, and a
timezone identifier outside the catalogued set.

### Timezone identifier policy

The accepted set is **one catalogued list shared by both hosts**:
`contracts/data/timezones/observing-night-zones.json` — the **catalogued shared
location-style timezone identifiers**, meaning the slash-form identifiers
present in *both* Foundation's `TimeZone.knownTimeZoneIdentifiers` and Python's
`zoneinfo.available_timezones()` for the audited runtime environment. Neither
platform's own parser defines the public API.

This is deliberately **not** a canonical-IANA-only set. Historical aliases and
backward links that both runtimes publish are included — `Asia/Calcutta`,
`Asia/Katmandu`, `Europe/Kiev`, `America/Godthab`, `Pacific/Ponape` and
`Pacific/Truk` among them, several of them alongside their modern spellings. The
guarantee the catalogue provides is *symmetry*: both hosts accept and reject
exactly the same identifiers. It is not a claim that every entry is the current
preferred name for its zone.

Rejected on **both** hosts even though one runtime parses them: fixed-offset
identifiers (`GMT-0800`, `GMT+0530`), bare `GMT` and `UTC`, `Etc/*`
pseudo-zones, non-location legacy names (`US/Pacific`, `EST5EDT`, `Zulu`), and
tzdata-private names (`right/UTC`, `posix/UTC`). An observing night is a
property of a place, so an identifier without a location is not a meaningful
input.

This governs the JSON transport only. The typed Swift API takes a `TimeZone`
directly and never reads the catalogue, which is what lets the iOS host keep its
existing `LocationTimeZoneResolver.approximate(longitude:)` fixed-offset
fallback unchanged — that value never crosses the transport.

## Local calendar operations

All day arithmetic uses a Gregorian calendar pinned to `time_zone` — production's
`ObservingCalendar.gregorian(for:)`. Exactly four Foundation `Calendar`
operations participate. Foundation does **not** apply one ambiguity policy across
them, so the Python side models each separately; the behaviour below was derived
from a differential scan of Foundation over every catalogued zone, sampling every
offset transition from 2000 to 2041 (130,558 `startOfDay`, 50,634
`date(byAdding:)` and 298,488 `dateComponents` observations).

1. **`startOfDay(for:)` — the first moment of the local civil day.** Resolving
   local midnight with `fold=0` reproduces it exactly: it takes the *earlier*
   occurrence of a repeated midnight, and on a day whose midnight is skipped it
   yields the transition instant (01:00 local).

2. **`date(byAdding: .day, value:)` — shifts the local civil date.** This is
   **not** `startOfDay`'s policy. Where the source instant's own UTC offset still
   reproduces the requested wall time, Foundation keeps that offset. On a
   repeated local midnight that selects the **later** occurrence — so
   `startOfDay(D) + (−1 day)` can be one hour *after* `startOfDay(D − 1)`.
   `America/Havana` on 2026-11-01 and `Atlantic/Azores` on 2026-10-25 are current
   examples. Only when the source offset cannot express the requested wall time
   does it fall back to the earliest-instant resolution, which is what produces
   the transition instant on a skipped local midnight.

3. **`dateComponents([.day], from:to:)`** — the largest signed whole-day count,
   toward zero, that still fits inside the interval, evaluated with operation 2.

4. **`isDate(_:inSameDayAs:)`** — equal local civil dates.

**Frozen quirk.** Because operations 2 and 3 work on wall clocks, a zone whose
DST transition is at local midnight can produce an elapsed-day count one lower
than the plain civil-date difference: from a `01:00` first moment to a `00:00`
first moment the next day, adding one day overshoots. `America/Santiago` on
2026-09-06 exercises this. It is production behaviour and is preserved.

### Dropped civil dates are outside the contract

A zone that crossed the date line dropped an entire civil date:
`Pacific/Apia` and `Pacific/Fakaofo` have no 2011-12-30, and Foundation's day
arithmetic there degenerates to plain 24-hour stepping in a way that is not
reproducible from the observable calendar rules. Rather than answer such a
payload differently on the two hosts, **both hosts reject it**: if any civil date
in the usable window — one day before the earlier of the reference and
forecast-start local dates, through 17 days after it — does not exist in the
resolved zone, the input is `validation`.

Only a missing civil *date* trips this. A missing *hour* never does, so every
ordinary DST zone, including `America/Havana`, `Atlantic/Azores` and
`America/Santiago`, is unaffected — and the affected zones themselves are
accepted for any window that does not contain the dropped date.

Beyond that window the two engines are free to differ: both daily arrays are
capped at 16 rows, so an elapsed-day count above 17 always fails the index guard
and yields `unavailable` whatever the exact number is. Python therefore stops
counting at 17 and Swift keeps Foundation's own value; the difference is
unobservable through this transport by construction. Multi-month spans crossing a
base-offset change are the only place the two counts would disagree.

## Day resolution

For a `day_offset` of `-1` or `0`:

```
reference_day = startOfDay(reference_time)
if forecast_start_time is present:
    elapsed = wholeDays(from: startOfDay(forecast_start_time), to: reference_day)
    day_index = elapsed + day_offset
else:
    day_index = day_offset
require day_index >= 0
require day_index < daily_sun_events.count
require day_index < daily_moon_count
observing_day_start = addDays(reference_day, day_offset)
today    = daily_sun_events[day_index]
tomorrow = daily_sun_events[day_index + 1] if it exists else none
astronomical_night_start = today.astronomical_twilight_end
astronomical_night_end   = tomorrow?.astronomical_twilight_begin
                           ?? today.astronomical_twilight_begin
```

If any requirement fails, that offset yields no night.

Two consequences are load-bearing and intentional:

- With `forecast_start_time: null` the index is the bare offset, so the
  preceding night can **never** resolve and offset `0` always selects row `0`
  whatever the reference date is.
- Without a following row, the night end falls back to the observing day's own
  morning twilight, which is **earlier** than the night start. The resulting
  window is empty, so such a night can be selected as the current night but can
  never be selected as an active preceding night.

## The decision

1. Resolve the night at `day_offset: -1`. If it exists and
   `astronomical_night_start <= reference_time <= astronomical_night_end`,
   the result is `resolved` with that night. **Both comparisons are inclusive.**
2. Otherwise resolve the night at `day_offset: 0`. If it does not exist, the
   result is `unavailable`.
3. If that night's observing day is the same local civil day as
   `reference_time` — always true at offset `0`, and reproduced rather than
   assumed away — **and** `reference_time <= daily_sun_events[day_index].astronomical_twilight_begin`
   (**inclusive**), the result is `requires_active_previous_payload`.
4. Otherwise the result is `resolved` with the offset-`0` night.

Step 3 says "an earlier astronomical night may still be running, but this
payload cannot resolve it". It is deliberately distinct from `unavailable`:
production hosts preserve an already-published previous-night payload in that
state, and discard everything in `unavailable`. Note that step 1 has priority,
so at an instant that is exactly the preceding night's end the preceding night
wins whenever it is resolvable at all.

## Output

Every key is always present. A state that carries no night reports JSON `null`
for the six night fields, which keeps the three states distinct.

| Field | Meaning |
| --- | --- |
| `state` | `resolved`, `requires_active_previous_payload` or `unavailable`. |
| `time_zone` | The identifier supplied by the caller, echoed because it participates in every calendar operation above. |
| `day_offset` | `-1` or `0`. |
| `day_index` | The index selected in the caller's daily arrays. |
| `observing_date` | The observing day as a local civil date, `YYYY-MM-DD`. |
| `observing_day_start` | The first moment of that observing day, as an instant. |
| `astronomical_night_start` / `astronomical_night_end` | The authoritative boundaries composed above. |

## Not in this capability

Timezone **acquisition** is host-owned and stays that way. Production's
precedence is: an explicitly supplied zone, then
`ViewingConditions.timeZoneIdentifier`, then
`LocationTimeZoneResolver.approximate(longitude:)`, a 15°-per-hour fixed GMT
offset used only when a `CLGeocoder` lookup failed or timed out. The first two
steps hand this capability an IANA identifier. The third produces a fixed-offset
zone with no IANA identity, so it cannot cross this transport; a non-Apple host
must resolve an IANA identifier of its own before asking. The typed Swift API
accepts any `TimeZone`, which is how the iOS host keeps its existing fallback
behaviour unchanged.

Also excluded: geocoding and provider fetching, Moon facts, hourly forecast
slicing, `NightQualityAnalyzer`, Night Conditions or Observing Quality scoring,
recommendation context assembly, widget/Watch payload lifecycle, cache
freshness, and every English label.

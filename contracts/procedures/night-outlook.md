# Three-night outlook day composition (unreleased 1.0)

Capabilities:

- `observing_night.compose_outlook`, `since: "1.0.0"`, `hosts: [ios, cli]`,
  equality `night_outlook`.
- `observing_night.select_best`, `since: "1.0.0"`, `hosts: [ios, cli]`,
  equality `night_outlook_best`.

**Deterministic**: every Sun, Moon and hourly fact is injected, so no provider,
ephemeris or scoring model runs here.

These are the portable form of the deterministic core of the production Swift
`ThreeNightOutlookWidgetPayloadBuilder`, now owned by
`AstroEngine.NightOutlookComposer`. Together they answer two questions and
nothing else: *which three observing nights does the outlook show, and can each
one carry a score*, and *which of the scored rows is the best night*.

## Boundary review

The production builder is mixed work. Archaeology separated it as follows.

**Engine-shaped, extracted here.**

- Day-slot composition. Slot 0 is the active observing night; slots 1 and 2 are
  the next two local civil days. Production derives the first slot's offset by
  differencing the local reference day against the resolved observing day, which
  is the exact inverse of the day shift that produced it, so the composed offsets
  are the active night's own offset plus 0, 1 and 2.
- Per-night semantic availability: `available`, `no_astronomical_night`,
  `unavailable`.
- The hourly-coverage rule that separates `available` from `unavailable`. It is
  a structural fact about whether the supplied stream covers the night, not a
  freshness or cache policy; production only *words* it as "Needs fresh data".
- All-or-nothing composition and the fallback rows that replace a
  non-composable outlook.
- Best-night eligibility, comparison and tie-breaking.

**Host-shaped, deliberately excluded.**

- `Tonight` / `Tomorrow` / `Day After`, verdict prose, status prose, score tone
  and every other string or colour. None of them is an input to any rule here:
  best-night selection reads only status and score.
- The scores themselves. Night Conditions and Observing Quality are already
  public capabilities; the host composes them and hands the headline score back
  to `observing_night.select_best`. Production resolves the brightness sample
  and location context **once** for the whole outlook, so all three nights share
  one score mode and a mixed-mode outlook is not producible; that is host
  composition, and neither capability can observe the mode.
- `bestWindow`, which belongs to `night_conditions.analyze`.
- AppGroup persistence, last-known-good retention, maximum age, stale-cache
  acceptance, widget reloads, timeline generation and location cache identity.
  In particular, `requires_active_previous_payload` is reported as a state; the
  decision to *preserve* an already-published payload in that state is host
  policy and stays in the builder.
- Authoritative IANA timezone acquisition, exactly as
  [`observing_night.resolve_active`](observing-night.md) already froze it. The
  production precedence — explicit zone, then `ViewingConditions.timeZoneIdentifier`,
  then `LocationTimeZoneResolver.approximate(longitude:)` — stays host-owned, and
  the longitude approximation has no IANA identity so it cannot cross the
  transport at all. The typed Swift API accepts any `TimeZone`, which keeps the
  iOS fallback byte-identical.

**Why two capabilities and not one.** The two rules run at different times.
Composition must finish before the host can know which nights exist and are
worth scoring; best-night selection can only run after those scores exist.
Folding them together would force a host to score nights it has not yet been
told exist, or to call the same capability twice. They are also independently
useful: the composition is a statement about days, the selection a statement
about already-scored rows.

**Why no third capability for hourly coverage.** Its only production consumer is
the classification in `compose_outlook`, and exposing it separately would
publish an internal step without a caller.

Rejected alternatives:

- **Reproducing `WidgetThreeNightOutlookSummary`.** It is a display-ready widget
  cache DTO: labels, verdicts, tone, status text, best window, generation time,
  location identity and two scores per row. Almost none of it is a portable
  Astro-domain fact.
- **A single capability that also scores the nights.** It would re-enter
  `night_conditions.analyze` and `observing_quality.assess` behind the caller's
  back and drag the whole hourly weather payload across the transport.
- **Re-deriving the active night here.** `observing_night.resolve_active` owns
  that decision; this capability calls it.
- **A generic N-night outlook.** Production composes exactly three; a count
  parameter would be invented behaviour.

## Composition procedure (`observing_night.compose_outlook`)

Inputs are those of `observing_night.resolve_active` plus the hourly timestamps:
`reference_time`, `time_zone`, `forecast_start_time`, `daily_sun_events`,
`daily_moon_count`, `hourly_times`.

1. Run the active-night decision exactly as
   [`observing_night.resolve_active`](observing-night.md) defines it, including
   its inclusive comparisons, day indexing, empty-hourly and missing-following-row
   quirks.
2. When it reports `requires_active_previous_payload`, the state is
   `requires_active_previous_payload`. When it reports `unavailable`, the state
   is `unavailable`. Both carry the fallback rows of step 6.
3. Otherwise resolve one night per slot at day offsets
   `active.day_offset + 0`, `+ 1`, `+ 2`, under the **same** guards — the day
   index must be non-negative and must exist in both daily arrays. Each resolved
   night's observing-day start, local date, and astronomical-night boundaries are
   those the active-night procedure defines for that offset.
4. If fewer than three slots resolve, the state is `unavailable` with the
   fallback rows of step 6. Composition is all-or-nothing; production never
   publishes a partial outlook.
5. Otherwise the state is `resolved` and each slot is classified:
   - `no_astronomical_night` when `start >= end`. Both boundaries are still
     reported.
   - `unavailable` when `start < end` but the hourly stream does not completely
     cover the window (below). Both boundaries are still reported.
   - `available` otherwise.
6. Fallback rows are the local reference day and the two days after it:
   `startOfDay(reference_time)` shifted by 0, 1 and 2 local days, with
   `day_offset` equal to the slot index, `day_index` null, both boundaries null
   and status `unavailable`.

### Hourly coverage

Hourly timestamps represent the **start** of their interval, so an interval may
contain a non-hour-aligned boundary. Over the whole stream, sorted ascending:

1. The nominal cadence is the median strictly positive step
   (`intervals[count / 2]` of the ascending positive steps, integer division).
   Zero and negative steps are excluded from the estimate but are not removed
   from the stream. With no positive step at all there is no cadence and the
   night is `unavailable`.
2. The cadence must be one hour within 60 s, otherwise the night is
   `unavailable`.
3. The covering rows are those with `time <= end` and `time + cadence >= start`.
   There must be at least one, the first must satisfy `time <= start`, and the
   last must satisfy `time + cadence >= end`.
4. Every consecutive pair of covering rows must step by the cadence within 60 s.
   A duplicate timestamp (step 0) or a missing hour (step 7200) therefore breaks
   coverage.

## Best-night procedure (`observing_night.select_best`)

Input is `nights`: up to three rows of `{status, score}`, in the composed order,
where `status` is one of the three composition statuses and `score` is the
host's headline score or null.

1. A row is eligible when `status == "available"` **and** `score` is not null.
   A row with a score but any other status never participates, and neither does
   an `available` row with no score.
2. With no eligible row the result is null.
3. Otherwise start from the first eligible row and replace the incumbent only on
   a **strictly greater** score. A tie therefore keeps the earliest eligible row,
   and the earliest row wins an all-equal outlook.
4. Nothing is sorted and no other field participates — not the day, not the
   window, not the tone or verdict, and not a separate Night Conditions score.

## Transport

`observing_night.compose_outlook` result:

```json
{
  "state": "resolved" | "requires_active_previous_payload" | "unavailable",
  "time_zone": "<supplied identifier>",
  "nights": [
    {
      "slot_index": 0,
      "day_offset": 0,
      "day_index": 0,
      "observing_date": "YYYY-MM-DD",
      "observing_day_start": "…Z",
      "astronomical_night_start": "…Z" | null,
      "astronomical_night_end": "…Z" | null,
      "status": "available" | "no_astronomical_night" | "unavailable"
    }
  ]
}
```

Every key is always present; a row that selected no day reports JSON null rather
than omitting the field, so the states never collapse under
`null_vs_omitted: distinct`.

`observing_night.select_best` result is `{"best_index": <integer> | null}`.

Zone, instant grammar (`YYYY-MM-DDThh:mm:ssZ`), the 2000-01-01T00:00:00Z through
2499-12-31T23:59:59Z instant range, the 16-day cap on `daily_sun_events` and
`daily_moon_count`, and the skipped-civil-date exclusion (`Pacific/Apia` and
`Pacific/Fakaofo` 2011-12-30) are exactly those of
[`observing_night.resolve_active`](observing-night.md), because this capability
composes over that decision. Composed observing-day starts must also stay inside
the instant range, so a reference day within two days of the range end is
refused rather than reported outside the transport's domain.

`hourly_times` is capped at 1440 rows, the shared 1.0 row cap. Caller order is
**not** semantics here: the coverage rule sorts on entry, exactly as production
does. `select_best` accepts at most three rows and scores in the closed range
0–100, which is what both public score capabilities clamp to.

Failures: `code: "validation"`, `message: "invalid <capability id> input"`.
Exceeding a cap is `code: "sample_cap"` with
`"<capability id> exceeds the 1.0 day cap (16 days)"`,
`"observing_night.compose_outlook exceeds the 1.0 row cap (1440 rows)"` or
`"observing_night.select_best exceeds the 1.0 row cap (3 rows)"`.

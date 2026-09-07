# Semantic cloud-timing classification (unreleased 1.0)

Capability: `night_conditions.classify_cloud_timing`, `since: "1.0.0"`,
`hosts: [ios, cli]`, equality `cloud_timing`. **Deterministic**: the hourly rows
are injected, so no forecast provider, astronomy model or night assessment runs
here.

This is the portable form of the production Swift
`NightQualityAnalysisRules.cloudTiming`, now owned by
`AstroEngine.CloudTimingClassifier`. It answers exactly one question — *when*
does sustained heavy cloud interrupt the night — and returns one of four
semantic verdicts.

## Boundary review

`NightQualityAnalyzer.generateSummary` is the only production consumer, and it
turns the verdict into English copy. That is a statement about the consumer, not
about the rule's home: the classification is a deterministic, calibration-driven
decision over astronomy/weather facts and is therefore engine-shaped, while the
copy is host presentation.

**The English summary text is deliberately not part of this contract.**
`CloudTiming.summaryText` stays in the Swift package as an iOS presentation
mapping; the Python engine does not reproduce it, no equality field covers it,
and a Bot host is free to word the advice however it likes — as long as it does
not invent the classification.

Verified against the production source before extraction:

- **The rule reads exactly three hourly facts**: `time`, `score`, `cloudCover`.
  `NightQualityAssessment.HourlyRating` also carries `id`, `fogScore`,
  `moonIllumination`, `moonAltitude`, `windSpeed`, `seeingScore` and
  `transparencyScore`; none of them can change the verdict, so none of them is
  transported.
- **The rule does not sort.** It iterates the array it is handed. Production
  happens to pass rows already sorted by time — `NightQualityAnalyzer` sorts the
  night forecasts before scoring them — but the classification itself is
  order-sensitive and caller order is therefore part of the contract. This is a
  deliberate difference from `observing_window.select`, which *does* sort.
- **No timezone or calendar is involved.** Only absolute timestamp deltas are
  compared, so the capability takes no IANA zone.
- **No override parameters.** Unlike `observing_window.select`, production's
  entry point exposes no threshold argument; both thresholds are read from the
  shared night-quality calibration.

Rejected alternatives:

- **Returning the whole `NightQualityAssessment`.** It would drag rating, trend,
  best window, details, per-hour provider facts and the English summary across
  the boundary; `night_conditions.analyze` already owns that shape.
- **Returning the chosen heavy-cloud interval** (start, length, average cloud).
  Production never publishes it; it is an internal ranking artefact, and
  exporting it would freeze an implementation detail as contract.
- **Exposing `summaryText`.** English is not a parity target, and making it one
  would force the Python engine and every Bot host to reproduce iOS copy.
- **Reusing `observing_window.select`'s row shape.** That row is `{time, score}`
  and is sorted on entry; this rule needs `cloud_cover` and must not sort.

## Calibration ownership

Both thresholds are already canonical in
`contracts/data/calibration/night-quality.json` and are read, not duplicated:

| Concept | Calibration key | Current value | Comparison |
|---|---|---|---|
| Heavy cloud | `cloud_floor.cloud_cover_min` | `80` | `cloud_cover >= min` (inclusive) |
| Usable hour | `rating_thresholds.fair_max` | `1.0` | `score < fair_max` (strict) |

Swift reads them through `EngineCalibration.current.nightQuality`; Python reads
the same file through `night_quality_calibration()`. Note that
`cloud_floor.fair_max` currently holds the same `1.0` value as
`rating_thresholds.fair_max` but is a *different* key and is **not** the one this
rule uses: production reaches the usable threshold through
`NightQualityAssessment.Rating.Thresholds.fairMax`, which is
`rating_thresholds.fair_max`.

## Algorithm (frozen production behavior)

1. **Sustained heavy-cloud runs.** Walk the rows in caller order. A row is heavy
   when `cloud_cover >= cloud_floor.cloud_cover_min`. A heavy row extends the
   current run only when `time[i] - time[i-1] == 3600` seconds exactly;
   otherwise it closes the current run and opens a new one at `i`. A non-heavy
   row closes the current run and opens none. A run is recorded only when it
   spans **at least two rows** (`end_index - start_index >= 1`), so a lone heavy
   hour never qualifies.
2. **Usable hours around a run.** `has_usable_before` is true when **any** row in
   the whole prefix `rows[:start_index]` has `score < fair_max`;
   `has_usable_after` is the same test over the whole suffix
   `rows[end_index+1:]`. These are not adjacency tests — a usable hour many rows
   away still counts.
3. **Eligibility, then ranking.** Runs with neither usable side are dropped
   **before** ranking. The remaining runs are ordered by greatest row count, then
   greatest average cloud cover, then earliest start index. That is a total
   order, because start indices are distinct.
4. **Verdict** from the preferred run's two flags:
   usable before only → `late_heavy`; usable after only → `early_heavy`; both →
   `intermittent_heavy`; neither → `none`. The last branch is unreachable after
   step 3 and is preserved verbatim.
5. **No eligible run** — including an empty input — is `none`.

### Preserved quirks

- **Exactly `3600`.** `3599`, `3601`, `0` (a duplicate timestamp), a negative
  delta and `7200` all break a run. Rows are never sorted first, so three heavy
  hours supplied out of order produce no run at all.
- **Minimum run size is two rows.** One heavy hour surrounded by clear, usable
  hours is `none`.
- **Heavy is inclusive, usable is strict.** `cloud_cover == 80` is heavy;
  `score == 1.0` is *not* usable.
- **Eligibility precedes ranking.** A longer ineligible run does not suppress a
  shorter eligible one; ranking first would return `none` where production
  returns a verdict.
- **A whole night of heavy cloud is `none`**, because the single run has no
  usable hour on either side.
- **Average cloud cover is `Double(sum of Int) / Double(count)`** in both hosts,
  compared with `!=` before the start-index tie break.

## Transport

Injected shape is exactly `{"hourly_ratings": [...]}`; each row is exactly
`{"time", "score", "cloud_cover"}`. Timestamps use the shared strict
`YYYY-MM-DDTHH:MM:SSZ` grammar. `score` is any finite JSON number, so a
threshold-equal `1.0` stays expressible. `cloud_cover` uses the shared engine
integer transport: booleans are not numbers, an integral float such as `80.0` is
accepted, and the magnitude bound is `1_000_000_000`.

Result is `{"cloud_timing": "none" | "early_heavy" | "late_heavy" |
"intermittent_heavy"}`.

Shape and value failures are `code: "validation"`,
`message: "invalid night_conditions.classify_cloud_timing input"`. More than
`1440` rows is `code: "sample_cap"`,
`message: "night_conditions.classify_cloud_timing exceeds the 1.0 row cap (1440 rows)"`
— one day of one-minute rows, the same 1.0 cap the other row-transport
capabilities use, and far above any real observing night.

The global Swift/Python `24:00:00Z` parser asymmetry is shared with the other
timestamp-carrying capabilities and stays a deferred pre-1.0 compatibility-gate
issue; it is not special-cased here.

## Production migration

`NightQualityAnalysisRules.cloudTiming(in:)` now maps its
`NightQualityAssessment.HourlyRating` rows to `CloudTimingClassifier.HourlyRow`
and delegates; the run detection, eligibility filter, ranking and verdict live in
`CloudTimingClassifier` only. `NightQualityAnalysisRules.CloudTiming` remains as
the production presentation alias that carries `summaryText`, so
`NightQualityAnalyzer.generateSummary` and every existing iOS summary string are
byte-for-byte unchanged.

`CloudTimingMigrationTests` compares the post-migration production entry point
against a verbatim copy of the pre-migration implementation over 203 974 nights:
an exhaustive sweep of every 0–4 row night drawn from three scores
(`0.5`, `1.0`, `1.5`), three cloud levels (`79`, `80`, `100`) and three
inter-row steps (`3600`, `0`, `3599`) — 183 961 nights — plus a deterministic
20 000-case sweep over 5–8 row nights with wider score, cloud and step alphabets
(including `3601`, `-3600`, `1800` and `7200`), plus 13 named production shapes.

## Out of scope

Forecast acquisition, the rest of `night_conditions.analyze`, trend, rating,
average-cloud prose, the seeing warning, best-window selection, provider data,
multi-night composition and every English string. Bot hosts may describe
authoritative hourly facts and may word cloud-timing advice themselves, but must
not re-derive the classification.

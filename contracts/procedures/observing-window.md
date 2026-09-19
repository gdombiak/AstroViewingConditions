# observing_window.select (unreleased 1.0)

## Boundary review

Initial assessment: **Agree** on clean `feature/astro-engine-cli` after Phase 16.
Production's best window affects Moon eligibility and scoring, so it is product
logic. Choose **B**, a small public deterministic decision with a new capability
ID, `observing_window.select`, `since: "1.0.0"`. The public count becomes 18;
engine/package identity remains unreleased 1.0.0, with no release declaration.

- **A**, extending `night_conditions.analyze`, changes an established DTO and
  equality boundary unnecessarily. Its procedure, output and fixtures stay intact.
- **C**, a night advisory capability, couples independent summary classifications
  and calendar adapters to a decision needing only scored rows.
- **D**, a host-owned language-neutral policy, would still need two authoritative
  implementations and tests. The shared engine already owns the production caller;
  exposing this small decision gives the Bot a direct authoritative operation.

## Input and validation

Use the standard capability/injected envelope. `injected` has exactly:

- required `hourly_ratings`: an array of objects with exactly `time` and `score`;
- optional `good_rating_threshold`: finite JSON number. When omitted, use
  `night-quality.json` → `rating_thresholds.fair_max` (currently 1.0).

Project `night_conditions.analyze.result.hourly_ratings` to `{time, score}`.
These are already included/scored rows, not raw forecasts. Do not supply darkness
bounds: upstream analysis clips to its explicit `[start,end)` injected window.
No clock, timezone, location, weather, Moon or provider facts are needed here.
Unknown injected/row fields, missing fields, nulls, booleans and nonfinite numbers
are invalid. Scores and thresholds are finite binary64 values; do not clamp them
or infer a category from an English label. Times are real Gregorian UTC instants
in exact `YYYY-MM-DDTHH:MM:SSZ` form, years 0001–9999, no offsets, fractions or leap
seconds. Reject an output outside that timestamp range as validation failure.
Input errors produce `validation`, message `invalid observing_window.select input`.
Standard envelope and confined `$ref` validation remain the dispatcher's concern.

## Normative decision

1. Stable-sort rows by timestamp ascending, retaining input order for equal times.
   Production sorts forecasts before scoring/traversal; do not deduplicate rows.
2. Empty rows return `{ "best_window": null }`.
3. A row qualifies iff `score < good_rating_threshold` (strict, despite the name
   the default is the fair/poor boundary, not the good/fair boundary).
4. If none qualify, select the first minimum-score row in sorted traversal.
   Return its timestamp through that timestamp plus exactly 3600 seconds.
5. If `Double(qualifying_count) / Double(total_count) >= 0.5`, return the first
   sorted timestamp through the last sorted timestamp. Neither endpoint is an
   astronomical bound; do not add an hour. A single qualifying row has zero duration.
6. Otherwise scan sorted rows. Each qualifying row adds exactly 3600 seconds to
   its run. A nonqualifying row terminates the run. Retain a run only when its
   row-count duration is strictly longer than the previous best; also consider
   the trailing run. Thus the earliest traversed equal-length run wins.
7. Return run start through run start plus its row-count duration. Do not test
   timestamp continuity or clip/extend to any astronomical/forecast boundary.

Output is exactly `{ "best_window": null | { "start": UTC, "end": UTC } }`.
Both timestamps and null/object presence use exact equality. This is an endpoint
pair, not a promise of positive duration, continuous coverage, or a half-open
sample-selection interval. Consumers retain their own endpoint comparisons.
Manual fixtures apply to `>=1.0.0 <2.0.0`; no prior fixture is changed.

## Adjacent production responsibilities

`NightQualityAnalyzer` delegates to the pure selector after scoring. Its
`NightQualityAssessment`, summaries, night endpoints and existing serialization
are unchanged. The pure selector has no astronomy dependency.

`DefaultMoonTargetRecommendationProvider.recommendation` uses bestWindow whenever
non-nil, even if zero-length; only nil falls back to context astronomical start/end.
It filters position samples **inclusively** at both endpoints, keeps altitude > 0,
and returns nil if none remain. The selected window subsequently affects best
sample, visible fraction, weather quality, score and reasons. This slice exposes
exactly the endpoint pair needed later; lunar parity is still outstanding.

`NightForecastFilter` lives in the engine package's Scoring directory. Its
calendar/DST projection is now separately portable through
`night_forecast.derive_window`; see the
[forecast-window procedure](night-forecast-window.md). `NightQualityAnalyzer`
filters `[start,end)` and sorts; `BestSpotSearcher` also uses the typed
`filterToNighttime` convenience. `TargetRecommendationContextBuilder` resolves
observing dates, timezone and forecasts, and separately supplies
SunEvents-derived Moon bounds. Bot host composition still needs to acquire those
inputs and call the capability; explicit injected bounds remain the clean
analysis interface.

`NightQualityAnalysisRules.cloudTiming` is consumed only by `generateSummary`
(and presentation tests), not window selection or recommendation eligibility or
scoring. Heavy cloud runs require >=2 rows exactly 3600 seconds apart, at the
configured cloud floor; eligible runs have usable-score rows before or after.
Preference is longest, then highest average cloud, then earliest start. The before/
after flags select late/early/intermittent-heavy, otherwise none; summary use also
depends on average cloud, rating and trend. That classification is engine-shaped
but outside both window capabilities: it is now its own slice,
`night_conditions.classify_cloud_timing` — see the
[cloud-timing procedure](cloud-timing.md). Bot hosts may describe authoritative
hourly facts and may word the advice themselves, but must not re-derive the
classification. English advice stays host presentation and is not parity-governed.

# Location score composition

Capability: `location.compose_scores`

## Composition boundary

This capability receives ordered, already-analyzed Best Nearby score facts. It
does not acquire weather, derive a night window, calculate Night Conditions or
Observing Quality, look up light pollution, inspect coordinates or suitability,
rank, truncate, or produce English copy.

Missing-weather grid points are omitted by the host before invocation. For each
remaining row, `has_nighttime_rows` is true exactly when the selected half-open
nighttime slice is nonempty. A host using `night_conditions.analyze` derives it
as `hourly_ratings` nonempty; partial-night coverage is sufficient.

Each candidate has exactly:

- `is_center`: Boolean.
- `night_conditions_score`: integer 0 through 100 inclusive.
- `has_nighttime_rows`: Boolean.
- `observing_quality.score`: integer 0 through 100 inclusive.
- `observing_quality.has_valid_light_pollution`: Boolean; true exactly when a
  valid light-pollution assessment participated. OQ score presence does not
  encode this fact.

Rows with `has_nighttime_rows == false` are excluded before all other decisions.
They do not affect mode or the center baseline. If no row survives, evaluation
fails with `error.code = no_scorable_locations` and message
`no scorable locations`.

More than one input center is invalid. Zero or one is accepted. A center supplies
the baseline only when it survives.

For a nonempty survivor set, mode is `observing_quality` exactly when every
survivor has valid light-pollution participation. Otherwise mode is
`night_conditions_fallback` for the whole set. Public score is respectively the
OQ score or Night Conditions score.

Output rows preserve survivor input order and contain `input_index`,
`public_score`, and `improvement_over_center`. The index is zero-based in the
original input array. When a scorable center exists, every delta is
`public_score - center_public_score`, including zero, negative values, and the
center's zero. Without one, every delta is null.

The JSON transport accepts at most 885 candidate rows, matching the largest
public `location.grid` result. This is a resource bound, not a Best Nearby
semantic candidate cap; the typed composition API is uncapped.

All object key sets are exact. Unknown or missing keys, non-Boolean Boolean
fields, and Boolean, fractional, or out-of-range scores are validation failures.

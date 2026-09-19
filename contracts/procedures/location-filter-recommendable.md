# Location recommendability filtering

Capability: `location.filter_recommendable`

## Filtering boundary

This capability receives an ordered `suitability` array containing only the
portable states `suitable`, `unknown`, `unchecked`, and `unsuitable`. Production
unknown-reason subtypes intentionally collapse to `unknown` because they do not
change eligibility.

`suitable` and `unknown` rows are included. `unchecked` and `unsuitable` rows are
excluded. The result is `recommendable_input_indices`, a stable array of
zero-based original indices. Empty input succeeds with an empty result.

The capability does not geocode, inspect reason or prose, inspect scores or
coordinates, rank, truncate, apply `topN`, or apply the Best Nearby candidate
band or 40-check cap. `location.compare` remains a separate unchanged authority.

The JSON transport accepts at most 885 suitability rows, matching the largest
public `location.grid` result. This is a resource bound only. The input object
key set is exact; unknown keys and non-enum values are validation failures.

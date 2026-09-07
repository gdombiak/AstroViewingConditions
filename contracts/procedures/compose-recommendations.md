# Mixed-target recommendation composition (unreleased 1.0)

Capability: `targets.compose_recommendations`, `since: "1.0.0"`,
`hosts: [ios, cli]`, equality `compose_recommendations`. **Deterministic**: the
scores and best times are injected, so no catalog, provider, scorer, weather
lookup or equipment matcher runs here.

This is the portable form of the *final* decision in the production
`DefaultTargetRecommendationService.recommendations(for:limit:)`: take the
candidate recommendations the host has already produced and turn them into the
ranked, truncated list the product shows.

## Boundary review

The service does four things: dispatch each catalog target to the right
provider, collect the resulting `TargetRecommendation` values, rank them
globally, and truncate. **Only the last two are portable.** Dispatch reads a
catalog, calls three different providers and depends on live astronomy and
weather; it stays in the host. What crosses the boundary is one ordering rule
over one three-field row.

Verified against the production service before extraction:

- **Moon and planets are never generically rescored.** The service routes a
  `.moon` target to `MoonTargetRecommendationProviding` and a `.planet` target to
  `PlanetTargetRecommendationProviding`, and only falls through to the position
  provider plus `DefaultTargetRecommendationScorer` when the specialized
  provider returns `nil`. That fall-through is production behavior and is
  preserved exactly; it is *not* a re-score of a specialized result, because the
  specialized result does not exist in that branch.
- **A specialized provider contributes at most one recommendation**, and the
  generic path contributes **one recommendation per visibility window**, so one
  target can contribute several rows. `flatMap` flattens both shapes into one
  candidate array.
- **Candidate input order is semantically significant.** It is the final tie
  breaker, so it is part of the contract and the transport never sorts or
  reorders rows during parsing.
- **No target type has priority independent of score and best time.** There is
  no type term, no alphabetical or id ordering, and no specialized tie breaker.
- **Reasons and English summaries are fixed at candidate creation** and are not
  touched afterwards. They are therefore not inputs to this capability.
- **The final debug logging is observational only** — a `#if DEBUG` block whose
  body is commented out — and cannot change the result.
- **Equipment filtering does not happen in this service.** It is applied outside
  it and is out of scope here.

Rejected alternatives:

- **A `targets.recommend_night` mega-capability** that owns catalog dispatch and
  all three providers. It would drag live astronomy, weather acquisition and
  three scoring models behind one identity and would make the Moon/planet
  boundary unenforceable.
- **Reusing `targets.recommend`'s output shape (keys only).** Production
  candidates are not key-unique — a deep-sky target with two windows yields two
  rows — so a key-only selection would be ambiguous. See the duplicate-key
  policy below.
- **Returning composed recommendation objects.** The host already holds the
  exact `TargetRecommendation` values, including reasons and localized summaries.
  Re-serializing them here would either lose or duplicate host presentation
  state; the capability returns identifiers instead.

## Inputs

Object with exactly `candidates` and `limit`. Nothing is optional.

- `candidates`: an ordered array of rows, each exactly `{key, score, best_time}`.
  The order is the caller's original candidate order and is the last tie
  breaker.
  - `key`: a non-empty string, the caller's stable identity for that candidate
    (production uses `TargetRecommendation.id`). It is echoed back and **never**
    participates in ordering.
  - `score`: an integral JSON number in `0 ... 100`. That is the production
    integer domain: `TargetRecommendation.init` clamps its score to that range,
    whichever scorer produced it. `5.0` is accepted as `5`; JSON booleans are not
    numbers.
  - `best_time`: a whole-second `Z` instant in
    `1999-12-31T22:00:00Z ... 2500-01-01T01:14:59Z`.
- `limit`: an integral JSON number with **no semantic bound**. Production is
  `prefix(max(0, limit))` over an array the row cap already bounds, so a limit
  above the cap can neither add work nor enlarge the output, and any negative
  value selects nothing. Only the shared engine integer transport applies — the
  same magnitude `targets.moon_recommendation` uses, `|limit| <= 1_000_000_000` —
  which keeps the value exactly representable in binary64 and in a Swift `Int` on
  every supported platform. The same transport governs `score`, which then adds
  its own `0 ... 100` production domain on top.

### Accepted instant range

`best_time` accepts the **union** of the `visibility_window` instant ranges the
three producing capabilities can emit. `targets.deep_sky_windows` and
`targets.moon_recommendation` stay inside the plain modern product range
`2000-01-01T00:00:00Z ... 2499-12-31T23:59:59Z`;
`targets.planet_recommendation` spills `-7200` (observation sampling lead) and
`+4500` (observation trail plus the fixed 900 s end-of-run extension) around it.
The widest of the three is therefore the accepted range here, so any mixed set of
production recommendations is composable **verbatim**. Both offsets are fixed
transport literals, not calibration reads. One second outside the range fails
closed.

### Duplicate keys

Duplicate `key` values are **accepted** and are never deduplicated. Production
can emit two candidates for one target — a deep-sky target with two visibility
windows — and the service does not deduplicate them, so neither may this
capability. Ordering never reads the key, and a selection is mapped back through
`index`, which is unique by construction. This is the one place the composition
transport deliberately differs from `targets.recommend`, whose `key` is its only
output handle and is therefore required unique there.

Resource bounds: `candidates` is capped at 1440 rows, checked on the array
before it is iterated, reporting `code: "sample_cap"`. Everything else reports
`code: "validation"` with `invalid targets.compose_recommendations input`.
Unknown keys anywhere fail closed. An empty `candidates` array is accepted and
yields an empty selection.

## Procedure

1. Order the candidate indices by, in order:
   1. `score` **descending**;
   2. `best_time` **ascending**;
   3. original input **index ascending**.
2. Take the first `max(0, limit)` of that order.
3. Emit each selected row as its original `index` and its echoed `key`, in that
   order.

A complete tie — equal score *and* equal best time — therefore preserves the
original candidate order. Scores, best times, reasons and summaries are never
mutated; this capability only chooses and orders.

`limit` greater than the candidate count — including far greater than the 1440
row cap — yields every candidate. `limit` of zero or any negative value yields an
empty selection. An empty candidate set yields an empty selection for every
accepted `limit`.

## Output

```
selected: [ { index, key }, ... ]
```

`index` is the 0-based position of the row in the input `candidates` array.
`key` is the input row's key, echoed unchanged. The array order **is** the
production display order.

No scores, no window endpoints, no reasons and no English copy are emitted. The
host maps `index` back onto the recommendation objects it already built, which
is what preserves reasons, summaries and every specialized field exactly.

## Composition boundary

Unlike `targets.moon_recommendation` and `targets.planet_recommendation`, this
capability's parity is **not** conditioned on a provider fact. Its inputs are
integers and whole-second instants, and every decision is an exact comparison on
them, so two hosts given the same rows agree unconditionally.

What is conditioned is the *rows*: the injected scores come from three different
capabilities, and a host that derives its own Moon or planet observation can
produce a different score and therefore a different order. That is the producing
capability's boundary, not this one's.

Specialized scores from all target types enter one global ranking. There is no
per-type bucket, no per-type quota and no re-scoring step between the specialized
providers and this composition.

## Equality

Policy `compose_recommendations`. `selected` is ordered and every element field
is exact. There are no floats and therefore no tolerances. Extra or missing
fields fail closed.

## Out of scope

Catalog dispatch, live astronomy, weather acquisition, generic target scoring,
Moon and planet scoring, deep-sky window generation, equipment-aware filtering,
host night/time composition, semantic advisory facts, Best Nearby and
location-set composition, multi-night forecast eligibility,
availability/failure/staleness semantics, English copy, and any change to
`targets.recommend`, `targets.moon_recommendation`,
`targets.planet_recommendation` or `targets.deep_sky_windows`.

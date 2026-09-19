# Cloud-advisory eligibility (unreleased 1.0)

Capability: `night_conditions.select_cloud_advisory`, `since: "1.0.0"`,
`hosts: [ios, cli]`, equality `cloud_advisory`.

Production's `NightQualityAnalyzer.generateSummary` first gives whole-night
heavy cloud precedence over timing advice. Otherwise it uses the timing summary
only for a non-poor overall rating and a non-`none` classification. This is a
portable Astro-domain decision, distinct from the English sentences that present
it. The selector consumes the already-authoritative output of
`night_conditions.classify_cloud_timing`; it never inspects hourly rows.

Injected input is exactly `{cloud_timing, rating, average_cloud_cover}`.
`cloud_timing` is one of `none`, `early_heavy`, `late_heavy`,
`intermittent_heavy`. `rating` is `excellent`, `good`, `fair`, or `poor`.
`average_cloud_cover` is a finite number in the production percentage range
0–100, equal to `night_conditions.analyze`'s `details.cloud_cover_score`.
Booleans are not numbers. No threshold override is accepted.

Read `cloud_floor.cloud_cover_min` from canonical night-quality calibration. If
average cloud cover is **greater than or equal to** that floor, return null; this
is the production whole-night-heavy priority. Otherwise return null if rating is
`poor` or cloud timing is `none`. Otherwise return the input timing code. Result
is exactly `{"cloud_advisory": null | "early_heavy" | "late_heavy" |
"intermittent_heavy"}`. `none` never means clear skies.

Invalid shape or value is `code: "validation"`, message
`invalid night_conditions.select_cloud_advisory input`. English strings, trend,
seeing warning, the clear-sky branch and every other rating-specific summary
branch stay outside this capability. Swift production's summary delegates the
eligibility decision and retains its prior branch order and copy. Astro Host
returns the result as a fact in `agent.conditions`; the Astronomer words it.

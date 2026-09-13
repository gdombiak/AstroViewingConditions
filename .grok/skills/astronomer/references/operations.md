# Astro Host operations

Pass exactly one JSON object on stdin to `scripts/astro.py OPERATION`. Preserve the
returned JSON until presentation; do not rewrite facts between operations.

## Conditions and recommendations

Both require a whole-second or otherwise ISO-8601 aware `reference_time`.
Omitting `location` uses the selected saved location. An explicit location is a
one-off override and does not change saved state.

```json
{"reference_time":"2026-09-12T04:00:00Z"}
```

An explicit location uses latitude and longitude, with optional `name`,
`elevation_m`, and authoritative `time_zone_hint` returned by place resolution:

```json
{"reference_time":"2026-09-12T04:00:00Z","location":{"latitude":45.4312,"longitude":-122.7715,"name":"Tigard, Oregon","time_zone_hint":"America/Los_Angeles"}}
```

`agent.conditions` accepts optional `observing_date` (`YYYY-MM-DD`) and
`force_refresh`. `agent.recommendations` accepts those fields plus optional
`equipment` and explicit `minimum_fit`. Do not send `minimum_fit` for the normal
request; omission is the production `any` behavior.

In `agent.conditions`, `result.night_conditions.cloud_timing` is the authoritative
classification. `result.night_conditions.cloud_advisory` is the nullable
authoritative eligibility fact for user-facing timing advice. Use the latter for
advice; do not recreate eligibility from rating, average cloud cover, hourly
weather, or the classification alone. Null does not assert clear skies.

`agent.outlook` is the canonical three-night outlook: the active observing night
plus the next two. It accepts `reference_time`, optional `location`, and optional
`force_refresh`. Do not send `observing_date`. Slot 0 is the active observing
night, including after local midnight.

Per-night `available`, `no_astronomical_night`, and `unavailable` are structural
Astro Engine statuses. Do not reinterpret them. A structurally `available` night
may still have a null `observing_quality` when host scoring could not produce a
headline score; that night is ineligible for best-night selection. Do not invent
a score. `best_index` is the authoritative best night, including earliest-wins
ties; identify “best night” only from that field. Wording such as “Tonight” or
“Tomorrow” is presentation over slot order.

This operation is implemented in the current source-tree host. It is not present
in the old experimental `astro-runtime-v0.1.0` wheels; the next clean Grok Bot
acceptance cycle uses newly built wheels from this tree.

## Named-place batch comparison

`agent.batch_compare` compares 1–16 caller-supplied named coordinates against an
optional `center`; omitting `center` uses the selected saved location. An explicit
center is one-time and does not mutate selection. The Bot discovery policy is at
most 8 destinations. The Host does not discover places. Names, URLs, and opaque
`metadata` round-trip unchanged and do not influence Astro scoring or ranking.

```json
{"reference_time":"2026-09-12T04:00:00Z","center":{"latitude":45.52,"longitude":-122.68,"time_zone_hint":"America/Los_Angeles"},"candidates":[{"key":"site-a","name":"Named Stargazing Area","latitude":45.7,"longitude":-122.5,"source_url":"https://example.org/site-a","map_url":"https://maps.google.com/?q=45.7,-122.5","metadata":{"access":"unknown"}}]}
```

`observing_date` (`YYYY-MM-DD`) and `force_refresh` are optional. The center's
IANA zone and requested observing night define the calendar context, including
after-midnight previous-date selection. Each destination uses its own coordinates
for weather, Sun/Moon, and light pollution. The Host uses cache/retry/stale
acquisition with at most three concurrent candidate calls. Engine
`location.compose_scores` chooses one coherent score mode and center deltas;
`location.compare` determines destination order. `location.distance` supplies
great-circle miles. `location.filter_recommendable` and grid suitability are not
part of this Bot operation.

In `result`, use `status`, `time_zone`, `observing_date`, `scoring_mode`,
`evaluated_count`, `ranked_destinations`, and `omitted_candidates`. A degraded
result may include stale weather, missing LP, or failed places; inspect each
row's `issues` and `acquisition`. A null `improvement_over_center` means the
center was unscorable, not zero improvement. `distance_miles` is straight-line,
never driving distance. Present the returned ranking without reordering it.
Access evidence remains outside Astro suitability; report official closures
and unknown access separately. Ordinary clickable Maps URLs are the supported
baseline. Native map cards, multi-pin maps, and built-in Places are unverified.

Equipment overrides are exactly one of:

```json
{"query":"S30"}
```

```json
{"id":"saved-equipment-uuid"}
```

```json
{"mode":"all_saved"}
```

```json
{"mode":"naked_eye_only"}
```

## Place resolution

Human place names always go through `agent.places`:

```json
{"action":"resolve","query":"Tigard, Oregon"}
```

Do not save a result until the user confirms. On confirmation, pass the exact
returned candidate object without dropping fields:

```json
{"action":"save_from_candidate","candidate":{RETURNED_CANDIDATE},"name":"Home","select":true}
```

`name`, `aliases`, and `select` are optional confirmation choices. Never
reconstruct provider identity, coordinates, timezone, usability, or ranking.

## Saved locations

Supported `agent.locations` requests are:

```json
{"action":"list"}
{"action":"get_selected"}
{"action":"clear_selection"}
{"action":"resolve","query":"Home"}
{"action":"get","id":"saved-location-uuid"}
{"action":"get","query":"Home"}
{"action":"select","id":"saved-location-uuid"}
{"action":"select","query":"Home"}
{"action":"delete","id":"saved-location-uuid"}
{"action":"delete","query":"Home"}
```

Direct coordinate saves are allowed only from user-confirmed facts and require an
authoritative IANA timezone:

```json
{"action":"save","location":{"name":"Home","latitude":45.4312,"longitude":-122.7715,"time_zone":"America/Los_Angeles"}}
```

## Saved equipment

Supported `agent.equipment` read/selection requests are:

```json
{"action":"list"}
{"action":"get_selected"}
{"action":"get_active"}
{"action":"resolve","query":"S30"}
{"action":"get","id":"saved-equipment-uuid"}
{"action":"get","query":"S30"}
{"action":"select","id":"saved-equipment-uuid"}
{"action":"select","query":"S30"}
{"action":"select_all"}
{"action":"select_naked_eye"}
{"action":"delete","id":"saved-equipment-uuid"}
{"action":"delete","query":"S30"}
```

Save only confirmed specifications. Types are `binoculars`, `visualTelescope`, or
`smartTelescope`; aperture units are `millimeters` or `inches`:

```json
{"action":"save","equipment":{"name":"S30 Pro","type":"smartTelescope","aperture":30,"aperture_unit":"millimeters"}}
```

Optional equipment fields are `magnification`, `aliases`, and `id`; optional
top-level `select:true` exclusively selects the newly saved item. Ordinarily omit
`select` so H12's all-saved default remains unchanged.

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

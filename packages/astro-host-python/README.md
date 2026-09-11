# astro-host (Python)

`astro-host` is the Python-only orchestration layer above `astro-engine`. Its
operations include `agent.conditions`, which turns a location and an aware
reference instant into typed weather, Sun/Moon, observing-night, Night
Conditions, best-window, cloud-timing, and optional Observing Quality facts;
and `agent.recommendations`, which answers “what should I observe tonight?”
from those same night facts plus H12 equipment.

The dependency direction is one-way:

```text
Bot / apps/cli/astro-host -> astro_host -> astro_engine
```

The host calls engine module APIs in-process. It does not invoke the engine CLI
or duplicate engine scoring, window, active-night, or classification rules.

## Typed API

```python
from datetime import datetime, timezone

from astro_host import (
    ConditionsRequest,
    ConditionsService,
    Location,
    MemoryLocationStore,
    SavedLocationDraft,
)

result = await ConditionsService().conditions(ConditionsRequest(
    location=Location(latitude=34.05, longitude=-118.24),
    reference_time=datetime.now(timezone.utc).replace(microsecond=0),
))
```

Timezone is normally derived automatically from the location. A valid saved
IANA hint wins; otherwise the host validates the IANA timezone returned by
Open-Meteo for the same coordinates. The longitude-derived fixed offset is
diagnostic only and cannot authorize calendar-sensitive engine calls. Missing
required twilight boundaries, including the first-slice polar case, produce a
structured `unavailable` result rather than invented boundaries.

Saved observing locations are a separate host-owned store. They are not the
weather cache and are not conversation memory. Every saved site has a stable
UUID, coordinates, and a mandatory authoritative IANA timezone. One location
may be selected as the default.

`ConditionsService` still takes an explicit `Location`. Orchestration above it
resolves a human place query (`agent.places`), persists a confirmed candidate
(`agent.locations` `save_from_candidate`) without re-geocoding, and fills
`agent.conditions` from the selected saved location when `location` is omitted.
An explicit location on `agent.conditions` is a one-off override: it wins over
the selected location and does not open or mutate the store. A resolved
candidate is not saved until that confirmation path.

```python
from astro_host import MemoryLocationStore, SavedLocationDraft

store = MemoryLocationStore()
home = store.save(SavedLocationDraft(
    name="Home",
    latitude=34.05,
    longitude=-118.24,
    time_zone="America/Los_Angeles",
    aliases=("house",),
))
assert store.get_selected() == home
```

Durable reuse is composition: construct `FileLocationStore(path)` or invoke
`agent.locations` so the CLI injects one. The default file is
`$ASTRO_HOST_STATE_DIR/locations.json`, else `~/.astro-host/locations.json`.
Pass `--locations-path` to override. Missing file is an empty first-run
directory; any other unreadable or foreign-schema document is an error, not
an empty list. Unknown v1 fields are preserved on rewrite.

Saved equipment is a third host-owned store, independent of locations and the
weather cache. Each item is a whole instrument — binoculars, visual telescope,
or smart/EAA telescope — with a stable UUID, unique name/aliases, and
user-entered aperture (plus magnification for binoculars). Naked Eye is a
built-in capability and is never stored. Selection is a three-way policy:
`all_saved` (default; Naked Eye plus every saved item), `item` (exactly one
saved instrument), or `naked_eye_only`. The first save does not exclusive-select.
`naked_eye_only` stays in force if inventory is deleted; it activates equipment
filtering even when no instruments are saved. Empty `all_saved` means no
equipment on file and does not filter.

```python
from astro_host import (
    EquipmentApertureUnit,
    EquipmentType,
    MemoryEquipmentStore,
    SavedEquipmentDraft,
    compose_active,
)

store = MemoryEquipmentStore()
store.save(SavedEquipmentDraft(
    name="S30 Pro",
    type=EquipmentType.SMART_TELESCOPE,
    aperture=30,
    aperture_unit=EquipmentApertureUnit.MILLIMETERS,
    aliases=("Seestar",),
))
active = compose_active(store.load())
assert active.source.value == "all_saved"
assert active.engine_has_saved_inventory is True
```

Durable reuse is composition: construct `FileEquipmentStore(path)` or invoke
`agent.equipment` so the CLI injects one. The default file is
`$ASTRO_HOST_STATE_DIR/equipment.json`, else `~/.astro-host/equipment.json`.
Pass `--equipment-path` to override. Missing file is an empty first-run
directory; any other unreadable or foreign-schema document is an error, not
an empty inventory. Unknown v1 fields are preserved on rewrite. An explicit
`get_active` equipment override never mutates the store. Override `mode` is
`all_saved` or `naked_eye_only` only; exclusive one-off use is `id` or `query`.

`agent.recommendations` reuses `ConditionsService.conditions` once for the same
location/night, then composes Moon, Venus/Mars/Jupiter/Saturn, and the 29
deep-sky catalog objects through existing engine capabilities. Mixed ranking is
`targets.compose_recommendations` with production limit 100. Equipment filtering
sees that whole pool, then the host slices the dashboard five. Omitted
`minimum_fit` is production `any`: selected equipment annotates `equipment_fit`
and does not change membership. Explicit `challengingOrBetter` / `goodOrBetter`
/ `excellentOnly` are echoed unchanged. The host does not rank, match, or
resolve requirements itself.

```python
from datetime import datetime, timezone

from astro_host import (
    ConditionsService,
    Location,
    LocationSource,
    MemoryEquipmentStore,
    RecommendationService,
    compose_active,
)

result = await RecommendationService(ConditionsService()).recommend(
    location=Location(latitude=34.05, longitude=-118.24),
    location_source=LocationSource.EXPLICIT_OVERRIDE,
    reference_time=datetime.now(timezone.utc).replace(microsecond=0),
    equipment=compose_active(MemoryEquipmentStore().load()),
)
```

## Weather lifecycle

The normal fresh-cache TTL is exactly 3600 seconds, matching the current
production normal-conditions cache. Cache reuse also requires matching
coordinates, past/forecast coverage, and local acquisition day; future
timestamps are invalid.

`ConditionsService()` still defaults to a process-local memory cache. Durable
reuse across CLI/Bot process restarts is **composition**: the CLI injects
`FileWeatherCache`. Setting `ASTRO_HOST_STATE_DIR` without that composition
does not persist anything. The one-hour freshness rule is unchanged.

Open-Meteo normally returns the current local day forward. For an active-night
request after midnight, the host first lets `observing_night.resolve_active`
identify that the preceding provider day is required, then performs one bounded
re-acquisition with `past_days=1` and retries composition. The provider supplies
the data; the engine remains the sole owner of active-night semantics.

Stale-on-error is separate and disabled by default. Callers may configure
`stale_on_error_max_age`; a stale result must still continuously cover the
selected night and is visibly `degraded` with stale provenance.

Open-Meteo timeout/network errors, HTTP 429, and selected transient 5xx statuses
use a small bounded retry/backoff policy. This is **Bot-host operational policy,
intentionally not Swift lifecycle parity**.

The CLI persists decoded weather snapshots in a versioned JSON file so multiple
locations and past/forecast coverage variants survive process restarts. Default
path is `$ASTRO_HOST_STATE_DIR/weather-cache.json`, else
`~/.astro-host/weather-cache.json`. Pass `--weather-cache-path` to override.
EMPTY snapshots are not stored; usable PARTIAL snapshots are. Stale-on-error
remains separately configurable and disabled by default. That file is host-owned
state; LLM conversation memory is never the cache.

## CLI

Install the engine and host packages, or use the checkout launcher:

```sh
apps/cli/astro-host agent.conditions --input request.json --pretty
apps/cli/astro-host agent.locations --input locations.json --pretty
apps/cli/astro-host agent.places --input places.json --pretty
apps/cli/astro-host agent.equipment --input equipment.json --pretty
apps/cli/astro-host agent.recommendations --input request.json --pretty
```

Use `--input -` for stdin. Optional `--weather-cache-path` selects the durable
weather JSON file; otherwise `$ASTRO_HOST_STATE_DIR/weather-cache.json` or
`~/.astro-host/weather-cache.json`. Optional `--locations-path` selects the
saved-location file; otherwise `$ASTRO_HOST_STATE_DIR/locations.json` or
`~/.astro-host/locations.json`. Optional `--equipment-path` selects the
saved-equipment file; otherwise `$ASTRO_HOST_STATE_DIR/equipment.json` or
`~/.astro-host/equipment.json`. The three files are independent: `agent.locations`
does not open the weather cache or equipment store, `agent.equipment` does not
open locations or weather, and `agent.places` does not open any of them.
`agent.conditions` opens the location store only when `location` is omitted, to
read the selected saved site. An explicit `location` object does not open the
store. `agent.recommendations` uses the same location rule, always opens the
equipment store for `get_active` projection, and shares one `ConditionsService`
(one weather acquisition) with `agent.conditions`. Compose remaps by index into
the mixed catalog array; filter remaps by index into compose survivors. The
output is a deterministic JSON envelope.
Complete, degraded, and unavailable domain results are successful envelopes;
invalid caller input and unexpected host failures have distinct nonzero exits.
A damaged locations file is `error.code=corrupt` or `unsupported_schema`, never
an empty success list.

Run tests from this directory with an environment containing the engine's dev
dependencies:

```sh
python -m pytest
```

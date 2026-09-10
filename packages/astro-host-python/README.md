# astro-host (Python)

`astro-host` is the Python-only orchestration layer above `astro-engine`. Its
first operation, `agent.conditions`, turns a location and an aware reference
instant into typed weather, Sun/Moon, observing-night, Night Conditions,
best-window, cloud-timing, and optional Observing Quality facts.

The dependency direction is one-way:

```text
Bot / apps/cli/astro-host -> astro_host -> astro_engine
```

The host calls engine module APIs in-process. It does not invoke the engine CLI
or duplicate engine scoring, window, active-night, or classification rules.

## Typed API

```python
from datetime import datetime, timezone

from astro_host import ConditionsRequest, ConditionsService, Location

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
```

Use `--input -` for stdin. Optional `--weather-cache-path` selects the durable
weather JSON file; otherwise `$ASTRO_HOST_STATE_DIR/weather-cache.json` or
`~/.astro-host/weather-cache.json`. The output is a deterministic JSON envelope.
Complete, degraded, and unavailable domain results are successful envelopes;
invalid caller input and unexpected host failures have distinct nonzero exits.

Run tests from this directory with an environment containing the engine's dev
dependencies:

```sh
python -m pytest
```

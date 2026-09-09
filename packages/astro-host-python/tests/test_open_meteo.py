from __future__ import annotations

import asyncio
from datetime import datetime, timezone
import json

import pytest

from astro_host.errors import HttpTransportError, WeatherProviderError
from astro_host.models import Location, PayloadState, ProviderFailureKind, WeatherQuery
from astro_host.providers.http import HttpResponse
from astro_host.providers.open_meteo import (
    OPEN_METEO_FORECAST_URL,
    OPEN_METEO_HOURLY_FIELDS,
    OpenMeteoPolicy,
    OpenMeteoWeatherProvider,
)


class FakeTransport:
    def __init__(self, outcomes):
        self.outcomes = list(outcomes)
        self.calls = []

    async def get(self, url, *, params, timeout_seconds):
        self.calls.append((url, params, timeout_seconds))
        outcome = self.outcomes.pop(0)
        if isinstance(outcome, Exception):
            raise outcome
        return outcome


def payload(*, optional=True):
    hourly = {
        "time": ["2026-02-19T00:00"],
        "cloudcover": [10], "relativehumidity_2m": [40],
        "windspeed_10m": [2.0], "winddirection_10m": [180],
        "temperature_2m": [10.0],
    }
    if optional:
        hourly.update({name: [0] for name in (
            "cloudcover_low", "cloud_cover_mid", "cloud_cover_high",
            "wind_speed_200hPa", "dewpoint_2m", "precipitation", "visibility",
        )})
    return {"timezone": "America/Los_Angeles", "utc_offset_seconds": -28800, "hourly": hourly}


def response(status=200, body=None, headers=None):
    document = payload() if body is None else body
    return HttpResponse(status, headers or {}, json.dumps(document).encode())


def provider(transport, sleeps=None, attempts=3):
    async def sleep(value):
        if sleeps is not None:
            sleeps.append(value)
    return OpenMeteoWeatherProvider(
        transport,
        policy=OpenMeteoPolicy(max_attempts=attempts, backoff_seconds=0.1),
        clock=lambda: datetime(2026, 2, 19, 12, tzinfo=timezone.utc),
        sleeper=sleep,
    )


def test_exact_params_timezone_and_provenance() -> None:
    transport = FakeTransport([response()])
    result = asyncio.run(provider(transport).fetch(WeatherQuery(Location(34.05, -118.24), 4)))
    url, params, timeout = transport.calls[0]
    assert url == OPEN_METEO_FORECAST_URL
    assert params == {
        "latitude": "34.05", "longitude": "-118.24",
        "hourly": ",".join(OPEN_METEO_HOURLY_FIELDS),
        "timezone": "auto", "forecast_days": "4",
    }
    assert timeout == 15
    assert result.provider_timezone == "America/Los_Angeles"
    assert result.utc_offset_seconds == -28800
    assert result.attempt_count == 1
    assert result.diagnostics.state is PayloadState.COMPLETE


def test_previous_day_parameter_is_added_only_when_requested() -> None:
    transport = FakeTransport([response()])
    query = WeatherQuery(Location(34.05, -118.24), 2, past_days=1)
    asyncio.run(provider(transport).fetch(query))
    assert transport.calls[0][1]["past_days"] == "1"

    with pytest.raises(WeatherProviderError) as exc:
        asyncio.run(provider(FakeTransport([])).fetch(
            WeatherQuery(Location(0, 0), 2, past_days=2)
        ))
    assert exc.value.failure.kind is ProviderFailureKind.INVALID_PAYLOAD
    assert exc.value.failure.attempt_count == 0


@pytest.mark.parametrize(
    "failure_kind", [ProviderFailureKind.TIMEOUT, ProviderFailureKind.NETWORK]
)
def test_transport_failures_retry(failure_kind) -> None:
    sleeps = []
    transport = FakeTransport([
        HttpTransportError(failure_kind, "temporary"), response()
    ])
    result = asyncio.run(provider(transport, sleeps).fetch(WeatherQuery(Location(0, 0), 2)))
    assert result.attempt_count == 2
    assert sleeps == [0.1]


def test_retry_exhaustion_preserves_attempt_count() -> None:
    transport = FakeTransport([
        HttpTransportError(ProviderFailureKind.TIMEOUT, "one"),
        HttpTransportError(ProviderFailureKind.TIMEOUT, "two"),
        HttpTransportError(ProviderFailureKind.TIMEOUT, "three"),
    ])
    with pytest.raises(WeatherProviderError) as exc:
        asyncio.run(provider(transport).fetch(WeatherQuery(Location(0, 0), 2)))
    assert exc.value.failure.kind is ProviderFailureKind.TIMEOUT
    assert exc.value.failure.attempt_count == 3
    assert len(transport.calls) == 3


@pytest.mark.parametrize("status", [500, 502, 503, 504])
def test_transient_5xx_retries(status) -> None:
    transport = FakeTransport([response(status), response()])
    result = asyncio.run(provider(transport).fetch(WeatherQuery(Location(0, 0), 2)))
    assert result.attempt_count == 2


def test_429_honors_sane_retry_after() -> None:
    sleeps = []
    transport = FakeTransport([response(429, headers={"Retry-After": "2"}), response()])
    result = asyncio.run(provider(transport, sleeps).fetch(WeatherQuery(Location(0, 0), 2)))
    assert result.attempt_count == 2
    assert sleeps == [2]


def test_permanent_4xx_does_not_retry() -> None:
    transport = FakeTransport([response(400)])
    with pytest.raises(WeatherProviderError) as exc:
        asyncio.run(provider(transport).fetch(WeatherQuery(Location(0, 0), 2)))
    assert exc.value.failure.kind is ProviderFailureKind.HTTP
    assert exc.value.failure.attempt_count == 1
    assert len(transport.calls) == 1


def test_invalid_json_does_not_retry() -> None:
    transport = FakeTransport([HttpResponse(200, {}, b"{"), response()])
    with pytest.raises(WeatherProviderError) as exc:
        asyncio.run(provider(transport).fetch(WeatherQuery(Location(0, 0), 2)))
    assert exc.value.failure.kind is ProviderFailureKind.INVALID_JSON
    assert len(transport.calls) == 1


def test_partial_empty_and_forecast_bounds() -> None:
    partial = FakeTransport([response(body=payload(optional=False))])
    result = asyncio.run(provider(partial).fetch(WeatherQuery(Location(0, 0), 2)))
    assert result.diagnostics.state is PayloadState.PARTIAL
    required_short = payload()
    required_short["hourly"]["cloudcover"] = []
    required = FakeTransport([response(body=required_short)])
    result = asyncio.run(provider(required).fetch(WeatherQuery(Location(0, 0), 2)))
    assert result.diagnostics.state is PayloadState.PARTIAL
    assert "short_required_series:cloudcover" in result.diagnostics.messages
    empty_payload = payload()
    empty_payload["hourly"]["time"] = []
    empty = FakeTransport([response(body=empty_payload)])
    result = asyncio.run(provider(empty).fetch(WeatherQuery(Location(0, 0), 2)))
    assert result.diagnostics.state is PayloadState.EMPTY
    with pytest.raises(WeatherProviderError) as exc:
        asyncio.run(provider(FakeTransport([])).fetch(WeatherQuery(Location(0, 0), 17)))
    assert exc.value.failure.attempt_count == 0
    with pytest.raises(WeatherProviderError) as exc:
        asyncio.run(provider(FakeTransport([])).fetch(WeatherQuery(Location(0, 0), 0)))
    assert exc.value.failure.attempt_count == 0

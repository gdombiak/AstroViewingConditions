from __future__ import annotations

import asyncio
import json

import pytest

from astro_host.errors import HttpTransportError, PlaceProviderError
from astro_host.models import ProviderFailureKind
from astro_host.providers.http import HttpResponse
from astro_host.providers.open_meteo import OpenMeteoPolicy
from astro_host.providers.open_meteo_geocoding import (
    OPEN_METEO_GEOCODING_URL,
    OpenMeteoPlaceResolver,
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


def portland_or(**overrides):
    row = {
        "id": 5746545,
        "name": "Portland",
        "latitude": 45.52345,
        "longitude": -122.67621,
        "elevation": 12.0,
        "timezone": "America/Los_Angeles",
        "country": "United States",
        "admin1": "Oregon",
        "admin2": "Multnomah County",
        "country_code": "US",
        "feature_code": "PPLA2",
        "population": 652503,
    }
    row.update(overrides)
    return row


def portland_me(**overrides):
    row = {
        "id": 4975802,
        "name": "Portland",
        "latitude": 43.657,
        "longitude": -70.2589,
        "timezone": "America/New_York",
        "country": "United States",
        "admin1": "Maine",
        "country_code": "US",
    }
    row.update(overrides)
    return row


def geocoding_body(results):
    if results is None:
        return {}
    return {"results": results}


def response(status=200, body=None, headers=None, results=None):
    if body is None:
        body = geocoding_body([] if results is None else results)
    encoded = body if isinstance(body, bytes) else json.dumps(body).encode()
    return HttpResponse(status, headers or {}, encoded)


def resolver(transport, sleeps=None, attempts=3):
    async def sleep(value):
        if sleeps is not None:
            sleeps.append(value)

    return OpenMeteoPlaceResolver(
        transport,
        policy=OpenMeteoPolicy(max_attempts=attempts, backoff_seconds=0.1),
        sleeper=sleep,
    )


def resolve(transport, query="Portland", **kwargs):
    return asyncio.run(resolver(transport, **kwargs).resolve(query))


def test_exact_url_params_and_core_fields() -> None:
    transport = FakeTransport([response(results=[portland_or()])])
    result = resolve(transport, "Portland")
    url, params, timeout = transport.calls[0]
    assert url == OPEN_METEO_GEOCODING_URL
    assert params == {
        "name": "Portland",
        "count": "10",
        "language": "en",
        "format": "json",
    }
    assert timeout == 15
    assert result.provider == "open_meteo"
    assert result.attempt_count == 1
    record = result.records[0]
    assert record.provider_place_id == 5746545
    assert record.name == "Portland"
    assert record.latitude == 45.52345
    assert record.longitude == -122.67621
    assert record.timezone == "America/Los_Angeles"
    assert record.elevation_m == 12.0
    assert record.country == "United States"
    assert record.admin1 == "Oregon"
    assert record.population == 652503


@pytest.mark.parametrize("body", [{}, {"results": None}, {"results": []}])
def test_empty_results_are_zero_records(body) -> None:
    result = resolve(FakeTransport([response(body=body)]))
    assert result.records == ()


def test_results_non_array_is_invalid_payload() -> None:
    with pytest.raises(PlaceProviderError) as exc:
        resolve(FakeTransport([response(body={"results": {"name": "Portland"}})]))
    assert exc.value.failure.kind is ProviderFailureKind.INVALID_PAYLOAD
    assert exc.value.failure.attempt_count == 1


def test_non_object_document_is_invalid_payload() -> None:
    with pytest.raises(PlaceProviderError) as exc:
        resolve(FakeTransport([response(body=b"[1]")]))
    assert exc.value.failure.kind is ProviderFailureKind.INVALID_PAYLOAD


def test_valid_or_malformed_coordinate_me_fails_payload() -> None:
    body = geocoding_body([
        portland_or(),
        portland_me(latitude="east"),
    ])
    with pytest.raises(PlaceProviderError) as exc:
        resolve(FakeTransport([response(body=body)]))
    assert exc.value.failure.kind is ProviderFailureKind.INVALID_PAYLOAD


def test_single_row_missing_latitude_fails_payload() -> None:
    row = portland_or()
    del row["latitude"]
    with pytest.raises(PlaceProviderError) as exc:
        resolve(FakeTransport([response(results=[row])]))
    assert exc.value.failure.kind is ProviderFailureKind.INVALID_PAYLOAD


def test_non_object_row_fails_payload() -> None:
    with pytest.raises(PlaceProviderError) as exc:
        resolve(FakeTransport([response(results=["Portland"])]))
    assert exc.value.failure.kind is ProviderFailureKind.INVALID_PAYLOAD


def test_empty_name_fails_payload() -> None:
    with pytest.raises(PlaceProviderError) as exc:
        resolve(FakeTransport([response(results=[portland_or(name="  ")])]))
    assert exc.value.failure.kind is ProviderFailureKind.INVALID_PAYLOAD


def test_optional_metadata_wrong_type_is_none_and_row_kept() -> None:
    result = resolve(FakeTransport([response(results=[portland_or(
        id="not-an-id",
        elevation="high",
        population=True,
        country={"name": "US"},
    )])]))
    record = result.records[0]
    assert record.name == "Portland"
    assert record.latitude == 45.52345
    assert record.provider_place_id is None
    assert record.elevation_m is None
    assert record.population is None
    assert record.country is None
    assert record.timezone == "America/Los_Angeles"


def test_non_string_timezone_is_kept_raw() -> None:
    result = resolve(FakeTransport([response(results=[portland_or(timezone=8)])]))
    assert result.records[0].timezone == 8
    assert result.records[0].name == "Portland"


def test_transport_timeout_retries() -> None:
    sleeps = []
    transport = FakeTransport([
        HttpTransportError(ProviderFailureKind.TIMEOUT, "temporary"),
        response(results=[portland_or()]),
    ])
    result = resolve(transport, sleeps=sleeps)
    assert result.attempt_count == 2
    assert sleeps == [0.1]


def test_429_and_5xx_retry() -> None:
    sleeps = []
    transport = FakeTransport([
        response(429, headers={"Retry-After": "2"}),
        response(503),
        response(results=[portland_or()]),
    ])
    result = resolve(transport, sleeps=sleeps)
    assert result.attempt_count == 3
    assert sleeps == [2, 0.2]


def test_400_and_invalid_json_do_not_retry() -> None:
    transport = FakeTransport([response(400), response(results=[portland_or()])])
    with pytest.raises(PlaceProviderError) as exc:
        resolve(transport)
    assert exc.value.failure.kind is ProviderFailureKind.HTTP
    assert exc.value.failure.attempt_count == 1
    assert len(transport.calls) == 1

    transport = FakeTransport([HttpResponse(200, {}, b"{"), response(results=[portland_or()])])
    with pytest.raises(PlaceProviderError) as exc:
        resolve(transport)
    assert exc.value.failure.kind is ProviderFailureKind.INVALID_JSON
    assert len(transport.calls) == 1

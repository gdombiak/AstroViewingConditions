"""Open-Meteo geocoding acquisition.

Retries reuse the shared Open-Meteo HTTP helper. Decode stays here: core
row structure fails the payload; timezone and optional metadata do not.
"""

from __future__ import annotations

import asyncio
import json
import math
from typing import Awaitable, Callable, Mapping

from astro_host.errors import PlaceProviderError
from astro_host.models import (
    PlaceProviderRecord,
    PlaceProviderResult,
    ProviderFailure,
    ProviderFailureKind,
)
from astro_host.providers.http import HttpTransport, UrllibHttpTransport
from astro_host.providers.open_meteo import (
    OpenMeteoPolicy,
    OpenMeteoRequestError,
    open_meteo_get,
)


OPEN_METEO_GEOCODING_URL = "https://geocoding-api.open-meteo.com/v1/search"
OPEN_METEO_GEOCODING_COUNT = "10"
OPEN_METEO_GEOCODING_LANGUAGE = "en"


class _CoreDecodeError(Exception):
    """A returned row is not a countable place."""


class OpenMeteoPlaceResolver:
    name = "open_meteo"

    def __init__(
        self,
        transport: HttpTransport | None = None,
        *,
        policy: OpenMeteoPolicy = OpenMeteoPolicy(),
        sleeper: Callable[[float], Awaitable[None]] = asyncio.sleep,
    ) -> None:
        self._transport = transport or UrllibHttpTransport()
        self._policy = policy
        self._sleep = sleeper

    async def resolve(self, query: str) -> PlaceProviderResult:
        params = {
            "name": query,
            "count": OPEN_METEO_GEOCODING_COUNT,
            "language": OPEN_METEO_GEOCODING_LANGUAGE,
            "format": "json",
        }
        try:
            response, attempt = await open_meteo_get(
                self._transport,
                OPEN_METEO_GEOCODING_URL,
                params,
                self._policy,
                self._sleep,
            )
        except OpenMeteoRequestError as exc:
            raise PlaceProviderError(exc.failure) from exc
        return self._decode_response(response.body, attempt)

    def _decode_response(self, body: bytes, attempt: int) -> PlaceProviderResult:
        try:
            payload = json.loads(body)
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise PlaceProviderError(ProviderFailure(
                kind=ProviderFailureKind.INVALID_JSON,
                message=f"Open-Meteo returned invalid JSON: {exc}",
                attempt_count=attempt,
                status_code=200,
            )) from exc
        if not isinstance(payload, dict):
            raise PlaceProviderError(ProviderFailure(
                kind=ProviderFailureKind.INVALID_PAYLOAD,
                message="Open-Meteo geocoding response must be a JSON object",
                attempt_count=attempt,
                status_code=200,
            ))
        if "results" not in payload or payload["results"] is None:
            return PlaceProviderResult(self.name, (), attempt)
        raw_results = payload["results"]
        if not isinstance(raw_results, list):
            raise PlaceProviderError(ProviderFailure(
                kind=ProviderFailureKind.INVALID_PAYLOAD,
                message="Open-Meteo geocoding results must be an array",
                attempt_count=attempt,
                status_code=200,
            ))
        records: list[PlaceProviderRecord] = []
        try:
            for index, item in enumerate(raw_results):
                records.append(_decode_row(item, index))
        except _CoreDecodeError as exc:
            raise PlaceProviderError(ProviderFailure(
                kind=ProviderFailureKind.INVALID_PAYLOAD,
                message=str(exc),
                attempt_count=attempt,
                status_code=200,
            )) from exc
        return PlaceProviderResult(self.name, tuple(records), attempt)


def _decode_row(item: object, index: int) -> PlaceProviderRecord:
    if not isinstance(item, Mapping):
        raise _CoreDecodeError(f"geocoding result {index} must be an object")
    name = item.get("name")
    if not isinstance(name, str) or not name.strip():
        raise _CoreDecodeError(
            f"geocoding result {index} name must be a non-empty string"
        )
    latitude = _core_coordinate(item.get("latitude"), "latitude", index, -90, 90)
    longitude = _core_coordinate(item.get("longitude"), "longitude", index, -180, 180)
    return PlaceProviderRecord(
        provider_place_id=_optional_int(item.get("id")),
        name=name.strip(),
        latitude=latitude,
        longitude=longitude,
        timezone=item.get("timezone"),
        elevation_m=_optional_finite_float(item.get("elevation")),
        country=_optional_string(item.get("country")),
        admin1=_optional_string(item.get("admin1")),
        admin2=_optional_string(item.get("admin2")),
        country_code=_optional_string(item.get("country_code")),
        feature_code=_optional_string(item.get("feature_code")),
        population=_optional_int(item.get("population")),
    )


def _core_coordinate(
    value: object, field: str, index: int, minimum: float, maximum: float
) -> float:
    if value is None:
        raise _CoreDecodeError(f"geocoding result {index} {field} is required")
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise _CoreDecodeError(
            f"geocoding result {index} {field} must be a number"
        )
    try:
        number = float(value)
    except OverflowError as exc:
        raise _CoreDecodeError(
            f"geocoding result {index} {field} must be finite"
        ) from exc
    if not math.isfinite(number) or not minimum <= number <= maximum:
        raise _CoreDecodeError(
            f"geocoding result {index} {field} must be finite and between "
            f"{minimum} and {maximum}"
        )
    return number


def _optional_string(value: object) -> str | None:
    if not isinstance(value, str):
        return None
    return value


def _optional_int(value: object) -> int | None:
    if isinstance(value, bool) or not isinstance(value, int):
        return None
    return value


def _optional_finite_float(value: object) -> float | None:
    if value is None or isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    try:
        number = float(value)
    except OverflowError:
        return None
    if not math.isfinite(number):
        return None
    return number

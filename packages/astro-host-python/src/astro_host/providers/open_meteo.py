"""Open-Meteo acquisition for the first host slice.

Retries are Bot-host operational policy, intentionally not Swift lifecycle
parity. The Astro Engine remains the only weather normalizer.
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from datetime import datetime, timezone
import json
import math
from typing import Awaitable, Callable, Mapping

from astro_host.errors import HttpTransportError, WeatherProviderError
from astro_host.models import (
    PayloadDiagnostics,
    PayloadState,
    ProviderFailure,
    ProviderFailureKind,
    WeatherProviderResponse,
    WeatherQuery,
)
from astro_host.providers.http import HttpResponse, HttpTransport, UrllibHttpTransport


OPEN_METEO_FORECAST_URL = "https://api.open-meteo.com/v1/forecast"
OPEN_METEO_HOURLY_FIELDS = (
    "cloudcover",
    "cloudcover_low",
    "cloud_cover_mid",
    "cloud_cover_high",
    "relativehumidity_2m",
    "windspeed_10m",
    "wind_speed_200hPa",
    "winddirection_10m",
    "temperature_2m",
    "dewpoint_2m",
    "precipitation",
    "visibility",
)
_REQUIRED_HOURLY_FIELDS = (
    "cloudcover",
    "relativehumidity_2m",
    "windspeed_10m",
    "winddirection_10m",
    "temperature_2m",
)
_OPTIONAL_HOURLY_FIELDS = (
    "cloudcover_low",
    "cloud_cover_mid",
    "cloud_cover_high",
    "wind_speed_200hPa",
    "dewpoint_2m",
    "precipitation",
    "visibility",
)
_TRANSIENT_STATUSES = frozenset({500, 502, 503, 504})


class OpenMeteoRequestError(Exception):
    """Shared HTTP/retry failure. Adapters wrap this in their provider error."""

    def __init__(self, failure: ProviderFailure) -> None:
        super().__init__(failure.message)
        self.failure = failure


@dataclass(frozen=True)
class OpenMeteoPolicy:
    timeout_seconds: float = 15.0
    max_attempts: int = 3
    backoff_seconds: float = 0.25
    max_retry_after_seconds: float = 5.0
    max_forecast_days: int = 16
    max_past_days: int = 1

    def __post_init__(self) -> None:
        if self.timeout_seconds <= 0:
            raise ValueError("timeout_seconds must be positive")
        if self.max_attempts < 1:
            raise ValueError("max_attempts must be at least one")
        if self.backoff_seconds < 0 or self.max_retry_after_seconds < 0:
            raise ValueError("retry delays must not be negative")
        if self.max_forecast_days < 1:
            raise ValueError("max_forecast_days must be at least one")
        if self.max_past_days < 0:
            raise ValueError("max_past_days must not be negative")


class OpenMeteoWeatherProvider:
    name = "open_meteo"

    def __init__(
        self,
        transport: HttpTransport | None = None,
        *,
        policy: OpenMeteoPolicy = OpenMeteoPolicy(),
        clock: Callable[[], datetime] = lambda: datetime.now(timezone.utc),
        sleeper: Callable[[float], Awaitable[None]] = asyncio.sleep,
    ) -> None:
        self._transport = transport or UrllibHttpTransport()
        self._policy = policy
        self._clock = clock
        self._sleep = sleeper

    async def fetch(self, query: WeatherQuery) -> WeatherProviderResponse:
        days = query.forecast_days
        if not 1 <= days <= self._policy.max_forecast_days:
            raise WeatherProviderError(ProviderFailure(
                kind=ProviderFailureKind.INVALID_PAYLOAD,
                message=(
                    f"forecast_days must be between 1 and "
                    f"{self._policy.max_forecast_days}"
                ),
                attempt_count=0,
            ))
        if not 0 <= query.past_days <= self._policy.max_past_days:
            raise WeatherProviderError(ProviderFailure(
                kind=ProviderFailureKind.INVALID_PAYLOAD,
                message=(
                    f"past_days must be between 0 and "
                    f"{self._policy.max_past_days}"
                ),
                attempt_count=0,
            ))

        params = {
            "latitude": str(query.location.latitude),
            "longitude": str(query.location.longitude),
            "hourly": ",".join(OPEN_METEO_HOURLY_FIELDS),
            "timezone": "auto",
            "forecast_days": str(days),
        }
        if query.past_days:
            params["past_days"] = str(query.past_days)

        try:
            response, attempt = await open_meteo_get(
                self._transport,
                OPEN_METEO_FORECAST_URL,
                params,
                self._policy,
                self._sleep,
            )
        except OpenMeteoRequestError as exc:
            raise WeatherProviderError(exc.failure) from exc
        return self._decode_response(response, attempt)

    def _decode_response(
        self, response: HttpResponse, attempt: int
    ) -> WeatherProviderResponse:
        try:
            payload = json.loads(response.body)
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise WeatherProviderError(ProviderFailure(
                kind=ProviderFailureKind.INVALID_JSON,
                message=f"Open-Meteo returned invalid JSON: {exc}",
                attempt_count=attempt,
                status_code=response.status,
            )) from exc
        if not isinstance(payload, dict):
            raise WeatherProviderError(ProviderFailure(
                kind=ProviderFailureKind.INVALID_PAYLOAD,
                message="Open-Meteo response must be a JSON object",
                attempt_count=attempt,
                status_code=response.status,
            ))

        provider_timezone = payload.get("timezone")
        if not isinstance(provider_timezone, str):
            provider_timezone = None
        offset = payload.get("utc_offset_seconds")
        if isinstance(offset, bool) or not isinstance(offset, int):
            offset = None

        return WeatherProviderResponse(
            provider=self.name,
            fetched_at=_as_utc(self._clock()),
            raw_payload=payload,
            provider_timezone=provider_timezone,
            utc_offset_seconds=offset,
            attempt_count=attempt,
            diagnostics=audit_open_meteo_payload(payload),
        )

async def open_meteo_get(
    transport: HttpTransport,
    url: str,
    params: Mapping[str, str],
    policy: OpenMeteoPolicy,
    sleeper: Callable[[float], Awaitable[None]],
) -> tuple[HttpResponse, int]:
    """GET with the shared Open-Meteo retry policy. Returns only HTTP 200."""
    last_transport_error: HttpTransportError | None = None
    for attempt in range(1, policy.max_attempts + 1):
        try:
            response = await transport.get(
                url,
                params=params,
                timeout_seconds=policy.timeout_seconds,
            )
        except HttpTransportError as exc:
            last_transport_error = exc
            if attempt < policy.max_attempts:
                await sleeper(_backoff(policy, attempt))
                continue
            raise OpenMeteoRequestError(ProviderFailure(
                kind=exc.kind,
                message=str(exc),
                attempt_count=attempt,
            )) from exc

        if response.status == 200:
            return response, attempt

        if response.status == 429:
            if attempt < policy.max_attempts:
                await sleeper(_retry_after(policy, response, attempt))
                continue
            raise _status_error(
                ProviderFailureKind.RATE_LIMITED, response.status, attempt
            )

        if response.status in _TRANSIENT_STATUSES:
            if attempt < policy.max_attempts:
                await sleeper(_backoff(policy, attempt))
                continue
            raise _status_error(
                ProviderFailureKind.HTTP, response.status, attempt
            )

        raise _status_error(ProviderFailureKind.HTTP, response.status, attempt)

    assert last_transport_error is not None
    raise OpenMeteoRequestError(ProviderFailure(
        kind=last_transport_error.kind,
        message=str(last_transport_error),
        attempt_count=policy.max_attempts,
    ))


def _status_error(
    kind: ProviderFailureKind, status: int, attempt: int
) -> OpenMeteoRequestError:
    return OpenMeteoRequestError(ProviderFailure(
        kind=kind,
        message=f"Open-Meteo returned HTTP {status}",
        attempt_count=attempt,
        status_code=status,
    ))


def _backoff(policy: OpenMeteoPolicy, attempt: int) -> float:
    return policy.backoff_seconds * (2 ** (attempt - 1))


def _retry_after(
    policy: OpenMeteoPolicy, response: HttpResponse, attempt: int
) -> float:
    raw = next(
        (value for key, value in response.headers.items() if key.lower() == "retry-after"),
        None,
    )
    try:
        parsed = float(raw) if raw is not None else math.nan
    except ValueError:
        parsed = math.nan
    if math.isfinite(parsed) and parsed >= 0:
        return min(parsed, policy.max_retry_after_seconds)
    return _backoff(policy, attempt)


def audit_open_meteo_payload(payload: Mapping[str, object]) -> PayloadDiagnostics:
    """Describe provider shape without reproducing weather decoding semantics."""
    hourly = payload.get("hourly")
    if not isinstance(hourly, Mapping):
        return PayloadDiagnostics(
            state=PayloadState.PARTIAL,
            messages=("missing_or_invalid_hourly_object",),
        )

    raw_times = hourly.get("time")
    if not isinstance(raw_times, list):
        return PayloadDiagnostics(
            state=PayloadState.PARTIAL,
            messages=("missing_or_invalid_hourly_series:time",),
        )
    time_count = len(raw_times)
    if time_count == 0:
        return PayloadDiagnostics(
            state=PayloadState.EMPTY,
            messages=("empty_hourly_time_series",),
            provider_time_count=0,
        )

    messages: list[str] = []
    for field in _REQUIRED_HOURLY_FIELDS:
        values = hourly.get(field)
        if not isinstance(values, list):
            messages.append(f"missing_or_invalid_required_series:{field}")
        elif len(values) < time_count:
            messages.append(f"short_required_series:{field}")
    for field in _OPTIONAL_HOURLY_FIELDS:
        values = hourly.get(field)
        if values is None:
            messages.append(f"missing_optional_series:{field}")
        elif not isinstance(values, list):
            messages.append(f"invalid_optional_series:{field}")
        elif len(values) < time_count:
            messages.append(f"short_optional_series:{field}")
    return PayloadDiagnostics(
        state=PayloadState.PARTIAL if messages else PayloadState.COMPLETE,
        messages=tuple(messages),
        provider_time_count=time_count,
    )


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("provider clock must return an aware datetime")
    return value.astimezone(timezone.utc)

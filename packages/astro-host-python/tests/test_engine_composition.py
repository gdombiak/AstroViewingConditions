from __future__ import annotations

import asyncio
from dataclasses import replace
from datetime import date, datetime, time, timedelta, timezone
import json
from zoneinfo import ZoneInfo

from astro_host.conditions import ConditionsService
from astro_host.engine import ConditionsEngine
from astro_host.models import (
    ConditionsRequest,
    ConditionsStatus,
    Location,
    PayloadDiagnostics,
    PayloadState,
    WeatherProviderResponse,
)
from astro_host.providers.http import HttpResponse
from astro_host.providers.open_meteo import (
    OpenMeteoPolicy,
    OpenMeteoWeatherProvider,
)

from support import NOW


class RawOpenMeteoProvider:
    name = "open_meteo"

    async def fetch(self, query):
        start = datetime(2026, 2, 19)
        times = [
            (start + timedelta(hours=index)).strftime("%Y-%m-%dT%H:%M")
            for index in range(query.forecast_days * 24)
        ]
        count = len(times)
        payload = {
            "timezone": "America/Los_Angeles",
            "utc_offset_seconds": -28_800,
            "hourly": {
                "time": times,
                "cloudcover": [10] * count,
                "cloudcover_low": [5] * count,
                "cloud_cover_mid": [3] * count,
                "cloud_cover_high": [2] * count,
                "relativehumidity_2m": [40] * count,
                "windspeed_10m": [2.0] * count,
                "wind_speed_200hPa": [30.0] * count,
                "winddirection_10m": [180] * count,
                "temperature_2m": [10.0] * count,
                "dewpoint_2m": [4.0] * count,
                "precipitation": [0.0] * count,
                "visibility": [10_000.0] * count,
            },
        }
        return WeatherProviderResponse(
            provider=self.name,
            fetched_at=NOW,
            raw_payload=payload,
            provider_timezone="America/Los_Angeles",
            utc_offset_seconds=-28_800,
            attempt_count=1,
            diagnostics=PayloadDiagnostics(PayloadState.COMPLETE, (), count),
        )


def test_real_engine_composition_crosses_local_midnight() -> None:
    service = ConditionsService(
        RawOpenMeteoProvider(),
        atlas_path=None,
        clock=lambda: NOW,
    )
    result = asyncio.run(service.conditions(
        ConditionsRequest(Location(34.05, -118.24), NOW)
    ))

    # No atlas is an optional degradation; all required in-process engine facts
    # still compose successfully.
    assert result.status is ConditionsStatus.DEGRADED
    assert result.timezone.iana_identifier == "America/Los_Angeles"
    assert result.selected_night is not None
    assert result.selected_night.observing_date is not None
    window = result.selected_night.forecast_window
    assert window is not None
    assert window.start < window.end

    assert result.weather is not None
    retained = tuple(row.time for row in result.weather.hourly)
    assert retained
    assert all(window.start <= value < window.end for value in retained)
    assert window.end not in retained

    assert result.astronomy is not None
    assert tuple(sample.time for sample in result.astronomy.moon_samples) == retained
    assert result.night_conditions is not None
    assert result.night_conditions.best_window is not None
    assert result.night_conditions.cloud_timing
    assert result.observing_quality is not None
    assert not result.observing_quality.light_pollution_available

    # The resolved observing interval is one local evening through the next
    # local morning, not a UTC-date guess.
    local_zone = ZoneInfo(result.timezone.iana_identifier)
    assert window.start.astimezone(local_zone).date() == result.selected_night.observing_date
    assert window.end.astimezone(local_zone).date() == (
        result.selected_night.observing_date + timedelta(days=1)
    )


class LocalCalendarTransport:
    """Fake HTTP surface with Open-Meteo's local-day range semantics."""

    def __init__(self, today: date, zone: ZoneInfo) -> None:
        self.today = today
        self.zone = zone
        self.calls: list[dict[str, str]] = []

    async def get(self, url, *, params, timeout_seconds):
        self.calls.append(dict(params))
        past_days = int(params.get("past_days", "0"))
        forecast_days = int(params["forecast_days"])
        first_day = self.today - timedelta(days=past_days)
        final_day = self.today + timedelta(days=forecast_days)
        cursor = datetime.combine(first_day, time.min, self.zone).astimezone(
            timezone.utc
        )
        end = datetime.combine(final_day, time.min, self.zone).astimezone(
            timezone.utc
        )
        times: list[str] = []
        while cursor < end:
            times.append(cursor.astimezone(self.zone).strftime("%Y-%m-%dT%H:%M"))
            cursor += timedelta(hours=1)
        count = len(times)
        payload = {
            "timezone": self.zone.key,
            "utc_offset_seconds": -25_200,
            "hourly": {
                "time": times,
                "cloudcover": [10] * count,
                "cloudcover_low": [5] * count,
                "cloud_cover_mid": [3] * count,
                "cloud_cover_high": [2] * count,
                "relativehumidity_2m": [40] * count,
                "windspeed_10m": [2.0] * count,
                "wind_speed_200hPa": [30.0] * count,
                "winddirection_10m": [180] * count,
                "temperature_2m": [10.0] * count,
                "dewpoint_2m": [4.0] * count,
                "precipitation": [0.0] * count,
                "visibility": [10_000.0] * count,
            },
        }
        return HttpResponse(200, {}, json.dumps(payload).encode())


def test_fresh_process_after_midnight_reacquires_previous_dst_day() -> None:
    # 01:30 PST immediately before the 2026 spring-forward transition. The
    # selected evening is March 7, while Open-Meteo's initial day is March 8.
    reference = datetime(2026, 3, 8, 9, 30, tzinfo=timezone.utc)
    local_zone = ZoneInfo("America/Los_Angeles")
    transport = LocalCalendarTransport(date(2026, 3, 8), local_zone)
    provider = OpenMeteoWeatherProvider(
        transport,
        policy=OpenMeteoPolicy(max_attempts=1),
        clock=lambda: reference,
    )
    service = ConditionsService(
        provider,
        atlas_path=None,
        clock=lambda: reference,
    )

    result = asyncio.run(service.conditions(
        ConditionsRequest(Location(34.05, -118.24), reference)
    ))

    assert result.status is ConditionsStatus.DEGRADED
    assert result.selected_night is not None
    assert result.selected_night.state == "resolved"
    assert result.selected_night.observing_date == date(2026, 3, 7)
    assert len(transport.calls) == 2
    assert "past_days" not in transport.calls[0]
    assert transport.calls[1]["past_days"] == "1"
    assert len(result.acquisition.provider_attempts) == 2
    assert all(
        attempt.state.value == "succeeded"
        for attempt in result.acquisition.provider_attempts
    )
    assert result.acquisition.snapshot is not None
    assert result.acquisition.snapshot.query.past_days == 1
    assert result.acquisition.snapshot.query.forecast_days == 2

    window = result.selected_night.forecast_window
    assert window is not None
    assert window.start.astimezone(local_zone).utcoffset() == timedelta(hours=-8)
    assert window.end.astimezone(local_zone).utcoffset() == timedelta(hours=-7)
    assert result.weather is not None
    assert result.weather.hourly[0].time < reference


class MissingUnrelatedTrailingSunEngine(ConditionsEngine):
    def sun_events(self, location, *, day, start, end):
        result = super().sun_events(
            location, day=day, start=start, end=end
        )
        if day == date(2026, 3, 9):
            return replace(result, astronomical_twilight_begin=None)
        return result


def test_after_midnight_ignores_unrelated_missing_third_sun_row() -> None:
    reference = datetime(2026, 3, 8, 9, 30, tzinfo=timezone.utc)
    local_zone = ZoneInfo("America/Los_Angeles")
    transport = LocalCalendarTransport(date(2026, 3, 8), local_zone)
    provider = OpenMeteoWeatherProvider(
        transport,
        policy=OpenMeteoPolicy(max_attempts=1),
        clock=lambda: reference,
    )
    service = ConditionsService(
        provider,
        engine=MissingUnrelatedTrailingSunEngine(),
        atlas_path=None,
        clock=lambda: reference,
    )

    result = asyncio.run(service.conditions(
        ConditionsRequest(Location(34.05, -118.24), reference)
    ))

    assert result.status is ConditionsStatus.DEGRADED
    assert result.selected_night is not None
    assert result.selected_night.observing_date == date(2026, 3, 7)
    assert result.night_conditions is not None
    assert {issue.code for issue in result.issues} == {
        "light_pollution_unavailable"
    }
    assert len(transport.calls) == 2

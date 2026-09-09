from __future__ import annotations

import asyncio
from dataclasses import replace
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from astro_host.cache import MemoryWeatherCache, covers_window, is_fresh, stale_allowed
from astro_host.models import (
    HourlyWeather, Location, PayloadDiagnostics, PayloadState, WeatherQuery,
    WeatherSnapshot,
)


NOW = datetime(2026, 2, 19, 20, tzinfo=timezone.utc)
ZONE = ZoneInfo("America/Los_Angeles")


def snapshot(*, age: float, days: int = 2, latitude: float = 34.05) -> WeatherSnapshot:
    fetched = NOW - timedelta(seconds=age)
    rows = tuple(
        HourlyWeather(
            time=datetime(2026, 2, 20, hour, tzinfo=timezone.utc),
            cloud_cover=10, humidity=40, wind_speed=2, wind_direction=0, temperature=10,
        )
        for hour in range(3, 14)
    )
    return WeatherSnapshot(
        query=WeatherQuery(Location(latitude, -118.24), days),
        provider="open_meteo", fetched_at=fetched,
        provider_timezone="America/Los_Angeles", utc_offset_seconds=-28800,
        hourly=rows, diagnostics=PayloadDiagnostics(PayloadState.COMPLETE, (), len(rows)),
    )


def test_freshness_boundary_future_and_local_day() -> None:
    query = WeatherQuery(Location(34.05, -118.24), 2)
    assert is_fresh(snapshot(age=3599), query, now=NOW, zone=ZONE)
    assert not is_fresh(snapshot(age=3600), query, now=NOW, zone=ZONE)
    assert not is_fresh(snapshot(age=-1), query, now=NOW, zone=ZONE)
    across_midnight = replace(
        snapshot(age=1),
        fetched_at=datetime(2026, 2, 20, 7, 50, tzinfo=timezone.utc),
    )
    just_after_midnight = datetime(2026, 2, 20, 8, 10, tzinfo=timezone.utc)
    assert not is_fresh(across_midnight, query, now=just_after_midnight, zone=ZONE)


def test_query_location_and_coverage_are_exact() -> None:
    cache = MemoryWeatherCache()
    entry = snapshot(age=10, days=4)
    asyncio.run(cache.put(entry))
    assert asyncio.run(cache.get(WeatherQuery(Location(34.05, -118.24), 2))) == entry
    assert asyncio.run(cache.get(WeatherQuery(Location(34.06, -118.24), 2))) is None
    assert asyncio.run(cache.get(WeatherQuery(Location(34.05, -118.24), 5))) is None
    assert asyncio.run(cache.get(
        WeatherQuery(Location(34.05, -118.24), 2, past_days=1)
    )) is None


def test_stale_fallback_requires_explicit_maximum() -> None:
    entry = snapshot(age=3600)
    assert not stale_allowed(entry, now=NOW, maximum_age=None)
    assert stale_allowed(entry, now=NOW, maximum_age=timedelta(hours=2))
    assert not stale_allowed(entry, now=NOW, maximum_age=timedelta(hours=1))


def test_window_coverage_requires_hourly_continuity() -> None:
    entry = snapshot(age=10)
    start = datetime(2026, 2, 20, 3, 30, tzinfo=timezone.utc)
    end = datetime(2026, 2, 20, 13, tzinfo=timezone.utc)
    assert covers_window(entry, start, end)
    broken = WeatherSnapshot(
        **{**entry.__dict__, "hourly": entry.hourly[:3] + entry.hourly[4:]}
    )
    assert not covers_window(broken, start, end)


def test_same_horizon_entries_with_different_past_coverage_coexist() -> None:
    cache = MemoryWeatherCache()
    normal = snapshot(age=30)
    richer = replace(
        snapshot(age=20),
        query=WeatherQuery(Location(34.05, -118.24), 2, past_days=1),
    )
    later_normal = replace(normal, fetched_at=NOW - timedelta(seconds=10))

    asyncio.run(cache.put(normal))
    asyncio.run(cache.put(richer))
    asyncio.run(cache.put(later_normal))

    assert asyncio.run(cache.get(
        WeatherQuery(Location(34.05, -118.24), 2, past_days=1)
    )) == richer
    assert asyncio.run(cache.get(
        WeatherQuery(Location(34.05, -118.24), 2, past_days=0)
    )) == later_normal

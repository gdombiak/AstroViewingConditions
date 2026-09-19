from __future__ import annotations

import asyncio
from dataclasses import replace
from datetime import datetime, timedelta, timezone, tzinfo
from zoneinfo import ZoneInfo

import pytest

from astro_host.cache import (
    MemoryWeatherCache, covers_window, is_fresh, snapshot_age, stale_allowed,
)
from astro_host.models import (
    HourlyWeather, Location, PayloadDiagnostics, PayloadState, WeatherQuery,
    WeatherSnapshot,
)


NOW = datetime(2026, 2, 19, 20, tzinfo=timezone.utc)
ZONE = ZoneInfo("America/Los_Angeles")
PROVIDER = "open_meteo"


def _clocked() -> MemoryWeatherCache:
    return MemoryWeatherCache(clock=lambda: NOW)


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
        provider=PROVIDER, fetched_at=fetched,
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
    assert asyncio.run(cache.get(
        WeatherQuery(Location(34.05, -118.24), 2), provider=PROVIDER,
    )) == entry
    assert asyncio.run(cache.get(
        WeatherQuery(Location(34.06, -118.24), 2), provider=PROVIDER,
    )) is None
    assert asyncio.run(cache.get(
        WeatherQuery(Location(34.05, -118.24), 5), provider=PROVIDER,
    )) is None
    assert asyncio.run(cache.get(
        WeatherQuery(Location(34.05, -118.24), 2, past_days=1), provider=PROVIDER,
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
        WeatherQuery(Location(34.05, -118.24), 2, past_days=1), provider=PROVIDER,
    )) == richer
    assert asyncio.run(cache.get(
        WeatherQuery(Location(34.05, -118.24), 2, past_days=0), provider=PROVIDER,
    )) == later_normal


def test_providers_do_not_share_identity() -> None:
    cache = MemoryWeatherCache()
    meteo = snapshot(age=10)
    other = replace(meteo, provider="other")
    query = WeatherQuery(Location(34.05, -118.24), 2)

    asyncio.run(cache.put(meteo))
    asyncio.run(cache.put(other))
    assert asyncio.run(cache.get(query, provider=PROVIDER)) == meteo
    assert asyncio.run(cache.get(query, provider="other")) == other

    asyncio.run(cache.put(replace(meteo, fetched_at=NOW)))
    assert asyncio.run(cache.get(query, provider="other")) == other


def test_empty_hourly_put_is_ignored() -> None:
    cache = MemoryWeatherCache()
    empty = replace(
        snapshot(age=10),
        hourly=(),
        diagnostics=PayloadDiagnostics(PayloadState.EMPTY, (), 0),
    )
    asyncio.run(cache.put(empty))
    assert asyncio.run(cache.get(empty.query, provider=PROVIDER)) is None


def test_future_put_does_not_replace_valid_identity() -> None:
    cache = _clocked()
    valid = snapshot(age=10)
    asyncio.run(cache.put(valid))
    asyncio.run(cache.put(replace(valid, fetched_at=NOW + timedelta(hours=1))))
    assert asyncio.run(cache.get(valid.query, provider=PROVIDER)) == valid


def test_future_richer_candidate_does_not_mask_older_usable() -> None:
    instant = {"now": NOW + timedelta(hours=1)}
    cache = MemoryWeatherCache(clock=lambda: instant["now"])
    older = snapshot(age=7200)
    richer = replace(
        snapshot(age=-1800),
        query=WeatherQuery(Location(34.05, -118.24), 2, past_days=1),
    )
    asyncio.run(cache.put(older))
    asyncio.run(cache.put(richer))
    instant["now"] = NOW
    query = WeatherQuery(Location(34.05, -118.24), 2)
    assert asyncio.run(cache.get(query, provider=PROVIDER)) == older
    assert asyncio.run(cache.get(
        WeatherQuery(Location(34.05, -118.24), 2, past_days=1), provider=PROVIDER,
    )) is None


def test_clock_rollback_makes_prior_snapshot_unselectable() -> None:
    instant = {"now": NOW}
    cache = MemoryWeatherCache(clock=lambda: instant["now"])
    entry = snapshot(age=0)
    asyncio.run(cache.put(entry))
    instant["now"] = NOW - timedelta(seconds=1)
    assert asyncio.run(cache.get(entry.query, provider=PROVIDER)) is None


def test_naive_fetched_at_put_does_not_replace_valid_identity() -> None:
    cache = _clocked()
    valid = snapshot(age=10)
    asyncio.run(cache.put(valid))
    asyncio.run(cache.put(replace(valid, fetched_at=NOW.replace(tzinfo=None))))
    assert asyncio.run(cache.get(valid.query, provider=PROVIDER)) == valid


def test_snapshot_age_naive_fetched_at_is_unusable() -> None:
    assert snapshot_age(
        replace(snapshot(age=10), fetched_at=NOW.replace(tzinfo=None)), NOW,
    ) is None


def test_snapshot_age_tzinfo_without_utcoffset() -> None:
    class no_offset(tzinfo):
        def utcoffset(self, dt):
            return None

        def dst(self, dt):
            return None

        def tzname(self, dt):
            return "NOOFFSET"

    pseudo = NOW.replace(tzinfo=no_offset())
    assert snapshot_age(replace(snapshot(age=10), fetched_at=pseudo), NOW) is None
    with pytest.raises(TypeError):
        snapshot_age(snapshot(age=10), pseudo)


def test_snapshot_age_non_datetime_fetched_at_propagates() -> None:
    with pytest.raises(AttributeError):
        snapshot_age(replace(snapshot(age=10), fetched_at="not-a-datetime"), NOW)


def test_snapshot_age_invalid_now_propagates() -> None:
    entry = snapshot(age=10)
    with pytest.raises(AttributeError):
        snapshot_age(entry, "not-a-datetime")
    with pytest.raises(TypeError):
        snapshot_age(entry, NOW.replace(tzinfo=None))


def test_non_datetime_fetched_at_put_propagates() -> None:
    cache = _clocked()
    with pytest.raises(AttributeError):
        asyncio.run(cache.put(replace(snapshot(age=10), fetched_at="not-a-datetime")))


def test_invalid_clock_put_propagates() -> None:
    valid = snapshot(age=10)
    with pytest.raises(AttributeError):
        asyncio.run(MemoryWeatherCache(clock=lambda: "not-a-datetime").put(valid))
    with pytest.raises(TypeError):
        asyncio.run(MemoryWeatherCache(clock=lambda: NOW.replace(tzinfo=None)).put(valid))

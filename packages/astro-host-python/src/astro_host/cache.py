"""Process-local weather cache for ``agent.conditions``."""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Protocol
from zoneinfo import ZoneInfo

from astro_host.models import WeatherQuery, WeatherSnapshot


FRESH_WEATHER_TTL = timedelta(seconds=3600)


class WeatherCache(Protocol):
    async def get(self, query: WeatherQuery) -> WeatherSnapshot | None: ...

    async def put(self, snapshot: WeatherSnapshot) -> None: ...


class MemoryWeatherCache:
    def __init__(self) -> None:
        self._entries: list[WeatherSnapshot] = []

    async def get(self, query: WeatherQuery) -> WeatherSnapshot | None:
        candidates = [
            entry
            for entry in self._entries
            if same_location(entry.query, query)
            and entry.query.forecast_days >= query.forecast_days
            and entry.query.past_days >= query.past_days
        ]
        if not candidates:
            return None
        return max(candidates, key=lambda entry: entry.fetched_at)

    async def put(self, snapshot: WeatherSnapshot) -> None:
        self._entries = [
            entry
            for entry in self._entries
            if not (
                same_location(entry.query, snapshot.query)
                and entry.query.forecast_days == snapshot.query.forecast_days
                and entry.query.past_days == snapshot.query.past_days
            )
        ]
        self._entries.append(snapshot)


def same_location(left: WeatherQuery, right: WeatherQuery) -> bool:
    return (
        left.location.latitude == right.location.latitude
        and left.location.longitude == right.location.longitude
    )


def snapshot_age(snapshot: WeatherSnapshot, now: datetime) -> timedelta | None:
    age = now - snapshot.fetched_at
    return age if age >= timedelta(0) else None


def is_fresh(
    snapshot: WeatherSnapshot,
    query: WeatherQuery,
    *,
    now: datetime,
    zone: ZoneInfo,
    ttl: timedelta = FRESH_WEATHER_TTL,
) -> bool:
    age = snapshot_age(snapshot, now)
    if age is None or age >= ttl:
        return False
    if not same_location(snapshot.query, query):
        return False
    if snapshot.query.forecast_days < query.forecast_days:
        return False
    if snapshot.query.past_days < query.past_days:
        return False
    return snapshot.fetched_at.astimezone(zone).date() == now.astimezone(zone).date()


def stale_allowed(
    snapshot: WeatherSnapshot,
    *,
    now: datetime,
    maximum_age: timedelta | None,
) -> bool:
    if maximum_age is None:
        return False
    age = snapshot_age(snapshot, now)
    return age is not None and age < maximum_age


def covers_window(snapshot: WeatherSnapshot, start: datetime, end: datetime) -> bool:
    """Whether hourly intervals continuously cover ``[start, end)``.

    This is cache eligibility, not a score or an astronomy classification.
    """
    if start >= end:
        return False
    times = sorted({row.time for row in snapshot.hourly})
    covering = [time for time in times if time < end and time + timedelta(hours=1) > start]
    if not covering:
        return False
    if covering[0] > start or covering[-1] + timedelta(hours=1) < end:
        return False
    return all(
        later - earlier <= timedelta(hours=1)
        for earlier, later in zip(covering, covering[1:])
    )

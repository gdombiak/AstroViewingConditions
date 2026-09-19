"""Process-local weather cache for ``agent.conditions``."""

from __future__ import annotations

from collections.abc import Callable, Sequence
from datetime import datetime, timedelta, timezone
from typing import Protocol
from zoneinfo import ZoneInfo

from astro_host.models import WeatherQuery, WeatherSnapshot


FRESH_WEATHER_TTL = timedelta(seconds=3600)


class WeatherCache(Protocol):
    async def get(
        self, query: WeatherQuery, *, provider: str
    ) -> WeatherSnapshot | None: ...

    async def put(self, snapshot: WeatherSnapshot) -> None: ...


class MemoryWeatherCache:
    def __init__(
        self,
        *,
        clock: Callable[[], datetime] = lambda: datetime.now(timezone.utc),
    ) -> None:
        self._entries: list[WeatherSnapshot] = []
        self._clock = clock

    async def get(
        self, query: WeatherQuery, *, provider: str
    ) -> WeatherSnapshot | None:
        return newest_usable_snapshot(
            self._entries, query, provider=provider, now=self._clock()
        )

    async def put(self, snapshot: WeatherSnapshot) -> None:
        if not snapshot.hourly:
            return
        if snapshot_age(snapshot, self._clock()) is None:
            return
        self._entries = [
            entry
            for entry in self._entries
            if not same_cache_identity(entry, snapshot)
        ]
        self._entries.append(snapshot)


def covering_snapshots(
    entries: Sequence[WeatherSnapshot],
    query: WeatherQuery,
    *,
    provider: str,
) -> list[WeatherSnapshot]:
    return [
        entry
        for entry in entries
        if entry.provider == provider
        and same_location(entry.query, query)
        and entry.query.forecast_days >= query.forecast_days
        and entry.query.past_days >= query.past_days
    ]


def newest_usable_snapshot(
    entries: Sequence[WeatherSnapshot],
    query: WeatherQuery,
    *,
    provider: str,
    now: datetime,
) -> WeatherSnapshot | None:
    candidates = [
        entry
        for entry in covering_snapshots(entries, query, provider=provider)
        if snapshot_age(entry, now) is not None
    ]
    if not candidates:
        return None
    return max(candidates, key=lambda entry: entry.fetched_at)


def same_cache_identity(left: WeatherSnapshot, right: WeatherSnapshot) -> bool:
    return (
        left.provider == right.provider
        and same_location(left.query, right.query)
        and left.query.forecast_days == right.query.forecast_days
        and left.query.past_days == right.query.past_days
    )


def same_location(left: WeatherQuery, right: WeatherQuery) -> bool:
    return (
        left.location.latitude == right.location.latitude
        and left.location.longitude == right.location.longitude
    )


def snapshot_age(snapshot: WeatherSnapshot, now: datetime) -> timedelta | None:
    if now.tzinfo is None or now.utcoffset() is None:
        raise TypeError("now must be timezone-aware")
    fetched_at = snapshot.fetched_at
    if fetched_at.tzinfo is None or fetched_at.utcoffset() is None:
        return None
    age = now - fetched_at
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
